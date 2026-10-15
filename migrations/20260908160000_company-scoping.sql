-- ============================================================================
-- companies — the vendor/brand a product catalog belongs to (e.g. Fresh,
-- Pran Chocolate). catalog_style picks which product-detail/order
-- representation the app renders for a company's products: 'simple' is the
-- existing pcs/jar/carton + single price model, 'trade_pricing' is the
-- DP/TP/MRP vendor price-list model (Pran Chocolate's sheet).
-- ============================================================================
CREATE TYPE public.catalog_style AS ENUM ('simple', 'trade_pricing');

CREATE TABLE public.companies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  catalog_style public.catalog_style NOT NULL DEFAULT 'simple',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER companies_updated_at BEFORE UPDATE ON public.companies
FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.companies TO authenticated;

CREATE POLICY companies_select ON public.companies FOR SELECT TO authenticated USING (true);

CREATE POLICY companies_write ON public.companies
  FOR ALL TO authenticated
  USING (public.current_role() = 'owner')
  WITH CHECK (public.current_role() = 'owner');

INSERT INTO public.companies (name, catalog_style) VALUES
  ('Fresh', 'simple'),
  ('Pran Chocolate', 'trade_pricing');

-- ============================================================================
-- profiles.company_id — which company a salesman is assigned to (Owner-set
-- via the Users screen, mirroring paired_deliveryman_id). Null for owner/
-- deliveryman, and for a salesman not yet assigned.
-- ============================================================================
ALTER TABLE public.profiles ADD COLUMN company_id UUID REFERENCES public.companies(id);
CREATE INDEX idx_profiles_company_id ON public.profiles(company_id);

CREATE OR REPLACE FUNCTION public.current_company_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT company_id FROM public.profiles WHERE user_id = auth.uid();
$$;

-- Extend the existing role/status guard so a non-owner can't self-assign or
-- change their own company either (same bootstrap carve-out role/status
-- already have, for the caller's own brand-new incomplete-profile row).
CREATE OR REPLACE FUNCTION public.guard_profile_privileges()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF (NEW.role IS DISTINCT FROM OLD.role
      OR NEW.status IS DISTINCT FROM OLD.status
      OR NEW.company_id IS DISTINCT FROM OLD.company_id)
     AND OLD.mobile IS NOT NULL
     AND public.current_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'only an owner can change role, status, or company';
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================================================
-- categories / products become company-scoped. Existing rows are today's
-- entire catalog, which is Fresh's (see seed-initial-catalog.sql — every
-- product is literally named "Fresh ...") — backfill them there.
-- ============================================================================
ALTER TABLE public.categories ADD COLUMN company_id UUID REFERENCES public.companies(id);
ALTER TABLE public.products ADD COLUMN company_id UUID REFERENCES public.companies(id);

UPDATE public.categories SET company_id = (SELECT id FROM public.companies WHERE name = 'Fresh');
UPDATE public.products SET company_id = (SELECT id FROM public.companies WHERE name = 'Fresh');

ALTER TABLE public.categories ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE public.products ALTER COLUMN company_id SET NOT NULL;
CREATE INDEX idx_categories_company_id ON public.categories(company_id);
CREATE INDEX idx_products_company_id ON public.products(company_id);

-- Trade-pricing reference columns — a vendor price-list snapshot, only
-- populated for trade_pricing companies (e.g. Pran Chocolate); NULL for
-- 'simple' companies like Fresh. product_units.price remains the one
-- authoritative, editable selling price used by every order/summary RPC;
-- these are Owner-facing reference fields alongside it, not used in order
-- math.
ALTER TABLE public.products
  ADD COLUMN item_code TEXT,
  ADD COLUMN factor INTEGER,
  ADD COLUMN dp_price NUMERIC(12,2),
  ADD COLUMN tp_price NUMERIC(12,2),
  ADD COLUMN mrp_price NUMERIC(12,2),
  ADD COLUMN sku_qty INTEGER,
  ADD COLUMN trade_qty INTEGER,
  ADD COLUMN jar_box_size INTEGER,
  ADD COLUMN after_trade_dp_price NUMERIC(12,2),
  ADD COLUMN after_trade_tp_price NUMERIC(12,2),
  ADD COLUMN per_pcs_dp_price NUMERIC(12,2),
  ADD COLUMN per_pcs_tp_price NUMERIC(12,2);

CREATE UNIQUE INDEX idx_products_company_item_code
  ON public.products(company_id, item_code) WHERE item_code IS NOT NULL;

-- ============================================================================
-- RLS: products/categories now scoped by company. Owner sees everything; a
-- salesman sees only their own company's active catalog; anyone (in
-- particular a deliveryman, who isn't assigned a company at all) can still
-- see a product they're already fulfilling via a daily_summary_item — the
-- delivery/summary detail screens do an unfiltered products.select('id,name')
-- lookup that must keep working regardless of company.
-- ============================================================================
DROP POLICY categories_select ON public.categories;
CREATE POLICY categories_select ON public.categories
  FOR SELECT TO authenticated
  USING (public.current_role() = 'owner' OR company_id = public.current_company_id());

DROP POLICY products_select ON public.products;
CREATE POLICY products_select ON public.products
  FOR SELECT TO authenticated
  USING (
    public.current_role() = 'owner'
    OR (is_active AND company_id = public.current_company_id())
    OR EXISTS (
      SELECT 1 FROM public.daily_summary_items dsi
      WHERE dsi.product_id = products.id AND public.can_view_summary(dsi.summary_id)
    )
  );

DROP POLICY product_units_select ON public.product_units;
CREATE POLICY product_units_select ON public.product_units
  FOR SELECT TO authenticated
  USING (
    public.current_role() = 'owner'
    OR EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = product_units.product_id AND p.company_id = public.current_company_id()
    )
  );

DROP POLICY stock_select ON public.stock;
CREATE POLICY stock_select ON public.stock
  FOR SELECT TO authenticated
  USING (
    public.current_role() = 'owner'
    OR EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = stock.product_id AND p.company_id = public.current_company_id()
    )
  );

DROP POLICY product_price_history_select ON public.product_price_history;
CREATE POLICY product_price_history_select ON public.product_price_history
  FOR SELECT TO authenticated
  USING (
    public.current_role() = 'owner'
    OR EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = product_price_history.product_id AND p.company_id = public.current_company_id()
    )
  );

DROP POLICY product_batches_select ON public.product_batches;
CREATE POLICY product_batches_select ON public.product_batches
  FOR SELECT TO authenticated
  USING (
    public.current_role() = 'owner'
    OR EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = product_batches.product_id AND p.company_id = public.current_company_id()
    )
  );

-- Expose company_id for convenient client-side grouping/filtering;
-- security_invoker means it still only returns what the caller's own (now
-- company-scoped) products/stock RLS already allows.
-- CREATE OR REPLACE VIEW requires existing column names/positions to stay
-- put — company_id is appended at the end rather than inserted where it
-- conceptually belongs, next to category_id.
CREATE OR REPLACE VIEW public.product_stock_view WITH (security_invoker = true) AS
SELECT
  p.id AS product_id,
  p.name,
  p.category_id,
  p.low_stock_threshold,
  s.unit_type,
  s.available_qty,
  s.damaged_qty,
  (s.available_qty <= p.low_stock_threshold) AS is_low_stock,
  p.company_id
FROM public.products p
JOIN public.stock s ON s.product_id = p.id;

GRANT SELECT ON public.product_stock_view TO authenticated;

-- ============================================================================
-- daily_summaries.company_id — one company per order. Backfill existing
-- rows (all Fresh) before making it required.
-- ============================================================================
ALTER TABLE public.daily_summaries ADD COLUMN company_id UUID REFERENCES public.companies(id);
UPDATE public.daily_summaries SET company_id = (SELECT id FROM public.companies WHERE name = 'Fresh')
  WHERE company_id IS NULL;
ALTER TABLE public.daily_summaries ALTER COLUMN company_id SET NOT NULL;
CREATE INDEX idx_daily_summaries_company_id ON public.daily_summaries(company_id);

-- ============================================================================
-- submit_daily_summary / edit_daily_summary — validate every line belongs to
-- the caller's own company and stamp company_id on newly-created summaries.
-- Supersedes the versions in 20260810140000_order-pcs-carton-rollup.sql.
-- ============================================================================
CREATE OR REPLACE FUNCTION public._upsert_summary_item(
  p_summary_id UUID,
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_quantity INTEGER,
  p_company_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_unit_price NUMERIC(12,2);
  v_existing_item_id UUID;
  v_existing_qty INTEGER;
  v_new_qty INTEGER;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = p_product_id AND company_id = p_company_id) THEN
    RAISE EXCEPTION 'product does not belong to your assigned company';
  END IF;

  SELECT pu.price INTO v_unit_price
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
    WHERE pu.product_id = p_product_id AND pu.unit_type = p_unit_type AND p.is_active;
  IF v_unit_price IS NULL THEN
    RAISE EXCEPTION 'no active price for the given product/unit';
  END IF;

  SELECT id, quantity INTO v_existing_item_id, v_existing_qty
    FROM public.daily_summary_items
    WHERE summary_id = p_summary_id AND product_id = p_product_id AND unit_type = p_unit_type
    FOR UPDATE;

  IF v_existing_item_id IS NOT NULL THEN
    v_new_qty := v_existing_qty + p_quantity;
    UPDATE public.daily_summary_items
      SET quantity = v_new_qty, unit_price = v_unit_price, line_total = v_unit_price * v_new_qty
      WHERE id = v_existing_item_id;
  ELSE
    INSERT INTO public.daily_summary_items (summary_id, product_id, unit_type, quantity, unit_price, line_total)
    VALUES (p_summary_id, p_product_id, p_unit_type, p_quantity, v_unit_price, v_unit_price * p_quantity);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._apply_summary_item(
  p_summary_id UUID,
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_quantity INTEGER,
  p_company_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_pcs_per_carton INTEGER;
  v_full_cartons INTEGER;
  v_remainder INTEGER;
  v_carton_price NUMERIC(12,2);
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be positive';
  END IF;

  IF p_unit_type = 'pcs' THEN
    SELECT pcs_per_carton INTO v_pcs_per_carton FROM public.products WHERE id = p_product_id;
    IF v_pcs_per_carton IS NOT NULL AND p_quantity >= v_pcs_per_carton THEN
      SELECT pu.price INTO v_carton_price
        FROM public.product_units pu
        JOIN public.products p ON p.id = pu.product_id
        WHERE pu.product_id = p_product_id AND pu.unit_type = 'carton' AND p.is_active;

      IF v_carton_price IS NOT NULL THEN
        v_full_cartons := p_quantity / v_pcs_per_carton;
        v_remainder := p_quantity % v_pcs_per_carton;

        PERFORM public._upsert_summary_item(p_summary_id, p_product_id, 'carton', v_full_cartons, p_company_id);
        IF v_remainder > 0 THEN
          PERFORM public._upsert_summary_item(p_summary_id, p_product_id, 'pcs', v_remainder, p_company_id);
        END IF;
        RETURN;
      END IF;
    END IF;
  END IF;

  PERFORM public._upsert_summary_item(p_summary_id, p_product_id, p_unit_type, p_quantity, p_company_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_daily_summary(p_items JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_summary_id UUID;
  v_item JSONB;
  v_total NUMERIC(12,2);
  v_company_id UUID;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'salesman' OR public.current_status() IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'only an active salesman can submit a daily summary';
  END IF;
  v_company_id := public.current_company_id();
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'you are not assigned to a company yet — ask the owner to assign one';
  END IF;
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'summary must contain at least one line item';
  END IF;

  SELECT id INTO v_summary_id
    FROM public.daily_summaries
    WHERE salesman_id = auth.uid() AND submission_date = current_date AND status = 'booked'
    FOR UPDATE;

  IF v_summary_id IS NULL THEN
    INSERT INTO public.daily_summaries (salesman_id, submission_date, delivery_date, total_amount, status, company_id)
    VALUES (auth.uid(), current_date, current_date + 1, 0, 'booked', v_company_id)
    RETURNING id INTO v_summary_id;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    PERFORM public._apply_summary_item(
      v_summary_id,
      (v_item->>'product_id')::UUID,
      (v_item->>'unit_type')::public.unit_type,
      (v_item->>'quantity')::INTEGER,
      v_company_id
    );
  END LOOP;

  SELECT COALESCE(SUM(line_total), 0) INTO v_total FROM public.daily_summary_items WHERE summary_id = v_summary_id;
  UPDATE public.daily_summaries SET total_amount = v_total, updated_at = now() WHERE id = v_summary_id;

  RETURN v_summary_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.submit_daily_summary(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.edit_daily_summary(p_summary_id UUID, p_items JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_summary RECORD;
  v_item JSONB;
  v_total NUMERIC(12,2);
BEGIN
  SELECT * INTO v_summary FROM public.daily_summaries WHERE id = p_summary_id FOR UPDATE;
  IF v_summary IS NULL THEN
    RAISE EXCEPTION 'summary not found';
  END IF;
  IF v_summary.salesman_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'not your summary';
  END IF;
  IF v_summary.status <> 'booked' OR v_summary.delivery_date <= current_date THEN
    RAISE EXCEPTION 'summary can no longer be edited';
  END IF;
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'summary must contain at least one line item';
  END IF;

  DELETE FROM public.daily_summary_items WHERE summary_id = p_summary_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    PERFORM public._apply_summary_item(
      p_summary_id,
      (v_item->>'product_id')::UUID,
      (v_item->>'unit_type')::public.unit_type,
      (v_item->>'quantity')::INTEGER,
      v_summary.company_id
    );
  END LOOP;

  SELECT COALESCE(SUM(line_total), 0) INTO v_total FROM public.daily_summary_items WHERE summary_id = p_summary_id;
  UPDATE public.daily_summaries SET total_amount = v_total, updated_at = now() WHERE id = p_summary_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.edit_daily_summary(UUID, JSONB) TO authenticated;
