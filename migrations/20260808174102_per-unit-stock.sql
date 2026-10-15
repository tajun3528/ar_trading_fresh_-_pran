-- Pieces, jars, and cartons are separate physical stock for this business —
-- a jar is not "N pieces packed together" and a carton is not "N jars
-- packed together." Track each unit type as its own independent stock count
-- per product; nothing converts into anything else.

-- Preserve any existing stock (currently all pieces-denominated) before
-- restructuring the table.
CREATE TEMP TABLE _stock_backup AS
  SELECT product_id, available_pcs, damaged_pcs FROM public.stock
  WHERE available_pcs != 0 OR damaged_pcs != 0;

DROP TRIGGER IF EXISTS products_create_stock ON public.products;
DROP FUNCTION IF EXISTS public.create_stock_row();

-- CASCADE removes the old stock_select policy and product_stock_view; both
-- are recreated below against the new shape.
DROP TABLE public.stock CASCADE;

CREATE TABLE public.stock (
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  unit_type public.unit_type NOT NULL,
  available_qty INTEGER NOT NULL DEFAULT 0 CHECK (available_qty >= 0),
  damaged_qty INTEGER NOT NULL DEFAULT 0 CHECK (damaged_qty >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (product_id, unit_type)
);

INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
SELECT product_id, 'pcs', available_pcs, damaged_pcs FROM _stock_backup;

CREATE TRIGGER stock_updated_at BEFORE UPDATE ON public.stock
FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();

ALTER TABLE public.stock ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.stock FROM authenticated;
GRANT SELECT ON public.stock TO authenticated;

CREATE POLICY stock_select ON public.stock
  FOR SELECT TO authenticated USING (true);

-- One row per product per unit type that has ever been stocked.
CREATE VIEW public.product_stock_view WITH (security_invoker = true) AS
SELECT
  p.id AS product_id,
  p.name,
  p.category_id,
  p.low_stock_threshold,
  s.unit_type,
  s.available_qty,
  s.damaged_qty,
  (s.available_qty <= p.low_stock_threshold) AS is_low_stock
FROM public.products p
JOIN public.stock s ON s.product_id = p.id;

GRANT SELECT ON public.product_stock_view TO authenticated;

-- ============================================================================
-- stock_in — no conversion; adds directly to that unit's own stock count.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.stock_in(
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_quantity INTEGER,
  p_entry_date DATE DEFAULT current_date
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'only the owner can record stock-in';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be positive';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = p_product_id) THEN
    RAISE EXCEPTION 'product not found';
  END IF;

  INSERT INTO public.stock_ins (product_id, unit_type, quantity, entry_date, entered_by)
  VALUES (p_product_id, p_unit_type, p_quantity, p_entry_date, auth.uid())
  RETURNING id INTO v_id;

  INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
  VALUES (p_product_id, p_unit_type, p_quantity, 0)
  ON CONFLICT (product_id, unit_type) DO UPDATE
    SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();

  RETURN v_id;
END;
$$;

-- ============================================================================
-- confirm_summary_delivery — checks/deducts the delivered unit's own stock
-- count directly; no cross-unit conversion.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.confirm_summary_delivery(p_summary_id UUID, p_items JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_summary RECORD;
  v_item JSONB;
  v_summary_item RECORD;
  v_delivery_id UUID;
  v_delivered_qty INTEGER;
  v_available INTEGER;
  v_fully_delivered BOOLEAN := true;
  v_seen_items INTEGER := 0;
  v_status public.order_status;
BEGIN
  SELECT * INTO v_summary FROM public.daily_summaries WHERE id = p_summary_id FOR UPDATE;
  IF v_summary IS NULL THEN
    RAISE EXCEPTION 'summary not found';
  END IF;
  IF v_summary.status NOT IN ('booked', 'partially_delivered') THEN
    RAISE EXCEPTION 'summary is not deliverable';
  END IF;
  IF NOT public.is_paired_deliveryman(v_summary.salesman_id) THEN
    RAISE EXCEPTION 'not your paired salesman';
  END IF;
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'delivery must contain at least one line item';
  END IF;

  INSERT INTO public.deliveries (summary_id, deliveryman_id, delivery_datetime, status)
  VALUES (p_summary_id, auth.uid(), now(), 'delivered')
  RETURNING id INTO v_delivery_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_summary_item FROM public.daily_summary_items
      WHERE id = (v_item->>'summary_item_id')::UUID AND summary_id = p_summary_id;
    IF v_summary_item IS NULL THEN
      RAISE EXCEPTION 'summary item not found on this summary';
    END IF;
    v_seen_items := v_seen_items + 1;

    v_delivered_qty := (v_item->>'delivered_quantity')::INTEGER;
    IF v_delivered_qty IS NULL OR v_delivered_qty < 0 THEN
      RAISE EXCEPTION 'delivered quantity must not be negative';
    END IF;
    IF v_delivered_qty > v_summary_item.quantity THEN
      RAISE EXCEPTION 'delivered quantity exceeds requested quantity';
    END IF;
    IF v_delivered_qty < v_summary_item.quantity THEN
      v_fully_delivered := false;
    END IF;

    SELECT available_qty INTO v_available FROM public.stock
      WHERE product_id = v_summary_item.product_id AND unit_type = v_summary_item.unit_type FOR UPDATE;
    IF v_available IS NULL OR v_available < v_delivered_qty THEN
      RAISE EXCEPTION 'insufficient % stock for product %', v_summary_item.unit_type, v_summary_item.product_id;
    END IF;

    UPDATE public.stock SET available_qty = available_qty - v_delivered_qty, updated_at = now()
      WHERE product_id = v_summary_item.product_id AND unit_type = v_summary_item.unit_type;

    INSERT INTO public.delivery_items (delivery_id, summary_item_id, delivered_quantity)
    VALUES (v_delivery_id, v_summary_item.id, v_delivered_qty);
  END LOOP;

  IF v_seen_items <> (SELECT count(*) FROM public.daily_summary_items WHERE summary_id = p_summary_id) THEN
    v_fully_delivered := false;
  END IF;

  v_status := CASE WHEN v_fully_delivered THEN 'delivered' ELSE 'partially_delivered' END::public.order_status;

  UPDATE public.deliveries SET status = v_status WHERE id = v_delivery_id;
  UPDATE public.daily_summaries SET status = v_status, updated_at = now() WHERE id = p_summary_id;

  RETURN v_delivery_id;
END;
$$;

-- ============================================================================
-- record_return — adds directly to that unit's own available/damaged count.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.record_return(
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_quantity INTEGER,
  p_condition public.return_condition,
  p_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_return_id UUID;
BEGIN
  IF public.current_role() NOT IN ('owner', 'deliveryman') THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be positive';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = p_product_id) THEN
    RAISE EXCEPTION 'product not found';
  END IF;

  IF p_condition = 'good' THEN
    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (p_product_id, p_unit_type, p_quantity, 0)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
  ELSE
    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (p_product_id, p_unit_type, 0, p_quantity)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET damaged_qty = public.stock.damaged_qty + EXCLUDED.damaged_qty, updated_at = now();
  END IF;

  INSERT INTO public.returns (product_id, unit_type, quantity, condition, reason, return_date, recorded_by)
  VALUES (p_product_id, p_unit_type, p_quantity, p_condition, p_reason, current_date, auth.uid())
  RETURNING id INTO v_return_id;

  RETURN v_return_id;
END;
$$;

-- No more unit conversion anywhere — drop the now-unused helper and columns.
DROP FUNCTION IF EXISTS public.to_pieces(UUID, public.unit_type, INTEGER);
ALTER TABLE public.products DROP COLUMN pcs_per_jar;
ALTER TABLE public.products DROP COLUMN pcs_per_carton;
ALTER TABLE public.stock_ins DROP COLUMN total_pcs;
