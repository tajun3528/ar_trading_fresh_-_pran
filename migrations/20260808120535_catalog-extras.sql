-- ============================================================================
-- product_price_history — append-only log of price changes over time.
-- product_units still holds the single current price used for order pricing
-- (FR-3.4); this table is purely informational so the Owner can see how a
-- price moved, without changing how book_order/edit_order price a line.
-- ============================================================================
CREATE TABLE public.product_price_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  unit_type public.unit_type NOT NULL,
  old_price NUMERIC(12,2),
  new_price NUMERIC(12,2) NOT NULL,
  changed_by UUID REFERENCES auth.users(id),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_product_price_history_lookup
  ON public.product_price_history(product_id, unit_type, changed_at);

ALTER TABLE public.product_price_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.product_price_history FROM authenticated;
GRANT SELECT ON public.product_price_history TO authenticated;

CREATE POLICY product_price_history_select ON public.product_price_history
  FOR SELECT TO authenticated USING (true);

CREATE OR REPLACE FUNCTION public.log_price_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.product_price_history (product_id, unit_type, old_price, new_price, changed_by)
    VALUES (NEW.product_id, NEW.unit_type, NULL, NEW.price, auth.uid());
  ELSIF TG_OP = 'UPDATE' AND NEW.price IS DISTINCT FROM OLD.price THEN
    INSERT INTO public.product_price_history (product_id, unit_type, old_price, new_price, changed_by)
    VALUES (NEW.product_id, NEW.unit_type, OLD.price, NEW.price, auth.uid());
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER product_units_log_price
AFTER INSERT OR UPDATE ON public.product_units
FOR EACH ROW EXECUTE FUNCTION public.log_price_change();

-- ============================================================================
-- product_batches — optional mfg/expiry tracking per product. Not tied into
-- stock movement logic (stock stays product-level per the approved schema);
-- this is reference data an owner can attach to a stock-in for traceability.
-- ============================================================================
CREATE TABLE public.product_batches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  batch_no TEXT NOT NULL,
  mfg_date DATE,
  expiry_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (product_id, batch_no)
);
CREATE INDEX idx_product_batches_product_id ON public.product_batches(product_id);
CREATE INDEX idx_product_batches_expiry_date ON public.product_batches(expiry_date);

ALTER TABLE public.product_batches ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.product_batches TO authenticated;

CREATE POLICY product_batches_select ON public.product_batches
  FOR SELECT TO authenticated USING (true);

CREATE POLICY product_batches_write ON public.product_batches
  FOR ALL TO authenticated
  USING (public.current_role() = 'owner')
  WITH CHECK (public.current_role() = 'owner');

ALTER TABLE public.stock_ins ADD COLUMN batch_id UUID REFERENCES public.product_batches(id);

-- ============================================================================
-- product_stock_view — ready-made low-stock projection (FR-5.6/5.8).
-- security_invoker means it shows exactly what the caller's own RLS on
-- products/stock already allows them to see — no extra policy needed.
-- ============================================================================
CREATE VIEW public.product_stock_view WITH (security_invoker = true) AS
SELECT
  p.id AS product_id,
  p.name,
  p.category_id,
  p.low_stock_threshold,
  s.available_pcs,
  s.damaged_pcs,
  (s.available_pcs <= p.low_stock_threshold) AS is_low_stock
FROM public.products p
JOIN public.stock s ON s.product_id = p.id;

GRANT SELECT ON public.product_stock_view TO authenticated;

-- ============================================================================
-- shop_ledger_view — per-shop payable/paid/due rollup (FR-9.3/9.6).
-- security_invoker means a salesman/deliveryman viewing this only ever sees
-- the shops their own route RLS already allows them to see.
-- ============================================================================
CREATE VIEW public.shop_ledger_view WITH (security_invoker = true) AS
SELECT
  s.id AS shop_id,
  s.name,
  s.route_id,
  COALESCE(o.total_payable, 0) AS total_payable,
  COALESCE(pay.total_paid, 0) AS total_paid,
  COALESCE(o.total_payable, 0) - COALESCE(pay.total_paid, 0) AS total_due
FROM public.shops s
LEFT JOIN (
  SELECT shop_id, SUM(payable_amount) AS total_payable
  FROM public.orders
  WHERE status IN ('delivered', 'partially_delivered')
  GROUP BY shop_id
) o ON o.shop_id = s.id
LEFT JOIN (
  SELECT shop_id, SUM(amount) AS total_paid
  FROM public.payments
  GROUP BY shop_id
) pay ON pay.shop_id = s.id;

GRANT SELECT ON public.shop_ledger_view TO authenticated;
