-- ============================================================================
-- Damage is no longer a per-line breakage on the round. What the deliveryman
-- actually collects is damaged and date-expired stock from shops — goods sold
-- on earlier rounds, from anywhere in the company's catalog, not just what is
-- in today's van. So it gets its own record.
--
-- Round arithmetic simplifies to  loaded = delivered + returned  and:
--
--   returned  → came back unsold; never left the shelf in the books, and its
--               value comes off the cash owed
--   damaged   → collected from the market; its value comes off the cash owed
--               as the shop's refund, but stock is untouched: those units
--               left when they were sold, and deducting them again would
--               remove the same goods from the shelf twice
--   delivered → the sale; this is what comes off available stock
--
-- Damage is valued at the salesman's own monthly selling price, so the refund
-- matches what the shop was charged.
-- ============================================================================
CREATE TABLE public.delivery_damages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id UUID NOT NULL REFERENCES public.deliveries(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id),
  unit_type public.unit_type NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(12,2) NOT NULL,
  line_total NUMERIC(12,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT delivery_damages_unique UNIQUE (delivery_id, product_id, unit_type)
);

CREATE INDEX delivery_damages_delivery ON public.delivery_damages (delivery_id);

ALTER TABLE public.delivery_damages ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.delivery_damages TO authenticated;

-- Visible to whoever can already see the delivery's summary; only the
-- deliveryman who owns the round writes to it.
CREATE POLICY delivery_damages_select ON public.delivery_damages
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.deliveries d
       WHERE d.id = delivery_damages.delivery_id
         AND (public.current_role() = 'owner' OR public.can_view_summary(d.summary_id))
    )
  );

CREATE POLICY delivery_damages_write ON public.delivery_damages
  FOR ALL TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.deliveries d
             WHERE d.id = delivery_damages.delivery_id AND d.deliveryman_id = auth.uid())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.deliveries d
             WHERE d.id = delivery_damages.delivery_id AND d.deliveryman_id = auth.uid())
  );

-- ============================================================================
-- What one unit sells for, for a given salesman in a given month — the same
-- fallback the order screen uses, but reachable without a summary so damaged
-- goods off any product can be priced.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.salesman_unit_price(
  p_salesman_id UUID,
  p_month DATE,
  p_product_id UUID,
  p_unit_type public.unit_type
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_price NUMERIC(12,2);
BEGIN
  SELECT selling_price INTO v_price
    FROM public.salesman_monthly_prices
   WHERE salesman_id = p_salesman_id
     AND product_id = p_product_id
     AND unit_type = p_unit_type
     AND month = date_trunc('month', p_month)::date;
  IF v_price IS NOT NULL THEN
    RETURN v_price;
  END IF;

  SELECT pu.price INTO v_price
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
   WHERE pu.product_id = p_product_id AND pu.unit_type = p_unit_type AND p.is_active;

  RETURN v_price;
END;
$$;

-- ============================================================================
-- close_delivery_round — returns come from the round's own lines; damages can
-- name any product in the company's catalog.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.close_delivery_round(
  p_delivery_id UUID,
  p_items JSONB,
  p_damages JSONB DEFAULT '[]'::jsonb
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_delivery RECORD;
  v_summary RECORD;
  v_item JSONB;
  v_line RECORD;
  v_returned INTEGER;
  v_delivered INTEGER;
  v_delivered_value NUMERIC(12,2) := 0;
  v_damaged_value NUMERIC(12,2) := 0;
  v_payment NUMERIC(12,2);
  v_fully_delivered BOOLEAN := true;
  v_status public.order_status;
  v_reported UUID[] := ARRAY[]::UUID[];
  v_product_id UUID;
  v_unit public.unit_type;
  v_qty INTEGER;
  v_price NUMERIC(12,2);
BEGIN
  SELECT * INTO v_delivery FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF v_delivery IS NULL THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;
  IF v_delivery.deliveryman_id <> auth.uid() THEN
    RAISE EXCEPTION 'not your delivery';
  END IF;
  IF v_delivery.loaded_at IS NULL THEN
    RAISE EXCEPTION 'load the van before closing the round';
  END IF;
  IF v_delivery.returns_recorded_at IS NOT NULL THEN
    RAISE EXCEPTION 'this round is already closed and waiting on owner approval';
  END IF;

  SELECT * INTO v_summary FROM public.daily_summaries WHERE id = v_delivery.summary_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT di.*, dsi.quantity AS ordered_quantity, dsi.unit_price
      INTO v_line
      FROM public.delivery_items di
      JOIN public.daily_summary_items dsi ON dsi.id = di.summary_item_id
     WHERE di.id = (v_item->>'delivery_item_id')::UUID AND di.delivery_id = p_delivery_id
     FOR UPDATE OF di;
    IF v_line IS NULL THEN
      RAISE EXCEPTION 'delivery line not found on this delivery';
    END IF;

    v_returned := COALESCE((v_item->>'returned_quantity')::INTEGER, 0);
    IF v_returned < 0 THEN
      RAISE EXCEPTION 'returned quantity must not be negative';
    END IF;
    IF v_returned > v_line.loaded_quantity THEN
      RAISE EXCEPTION 'returned is more than what was loaded into the van';
    END IF;

    v_delivered := v_line.loaded_quantity - v_returned;
    IF v_delivered < v_line.ordered_quantity THEN
      v_fully_delivered := false;
    END IF;

    UPDATE public.delivery_items
       SET returned_quantity = v_returned,
           damaged_quantity = 0,
           delivered_quantity = v_delivered
     WHERE id = v_line.id;

    v_reported := v_reported || v_line.id;
    v_delivered_value := v_delivered_value + v_delivered * v_line.unit_price;
  END LOOP;

  -- Anything that went out but wasn't reported on came back unsold.
  UPDATE public.delivery_items
     SET returned_quantity = loaded_quantity,
         damaged_quantity = 0,
         delivered_quantity = 0
   WHERE delivery_id = p_delivery_id
     AND NOT (id = ANY(v_reported));

  IF EXISTS (
    SELECT 1 FROM public.delivery_items di
      JOIN public.daily_summary_items dsi ON dsi.id = di.summary_item_id
     WHERE di.delivery_id = p_delivery_id AND di.delivered_quantity < dsi.quantity
  ) THEN
    v_fully_delivered := false;
  END IF;

  -- Collected damage, re-recorded from scratch so a corrected submission
  -- replaces rather than adds to what was there.
  DELETE FROM public.delivery_damages WHERE delivery_id = p_delivery_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_damages, '[]'::jsonb)) LOOP
    v_product_id := (v_item->>'product_id')::UUID;
    v_unit := (v_item->>'unit_type')::public.unit_type;
    v_qty := COALESCE((v_item->>'quantity')::INTEGER, 0);
    IF v_qty <= 0 THEN
      CONTINUE;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.products WHERE id = v_product_id AND company_id = v_summary.company_id
    ) THEN
      RAISE EXCEPTION 'damaged product does not belong to this order''s company';
    END IF;

    v_price := public.salesman_unit_price(
      v_summary.salesman_id, v_summary.delivery_date, v_product_id, v_unit);
    IF v_price IS NULL THEN
      RAISE EXCEPTION 'no price available for the damaged product/unit';
    END IF;

    INSERT INTO public.delivery_damages (delivery_id, product_id, unit_type, quantity, unit_price, line_total)
    VALUES (p_delivery_id, v_product_id, v_unit, v_qty, v_price, v_price * v_qty);

    v_damaged_value := v_damaged_value + v_price * v_qty;
  END LOOP;

  v_payment := v_delivered_value - COALESCE(v_summary.commission_amount, 0) - v_damaged_value;

  v_status := CASE WHEN v_fully_delivered THEN 'delivered' ELSE 'partially_delivered' END::public.order_status;
  UPDATE public.deliveries
     SET status = v_status,
         returns_recorded_at = now(),
         delivery_datetime = now(),
         payment_amount = v_payment
   WHERE id = p_delivery_id;

  RETURN v_payment;
END;
$$;

DROP FUNCTION IF EXISTS public.close_delivery_round(UUID, JSONB);
GRANT EXECUTE ON FUNCTION public.close_delivery_round(UUID, JSONB, JSONB) TO authenticated;

-- ============================================================================
-- approve_delivery — only the sale moves stock now. Collected damage is a
-- refund against goods that left the shelf on an earlier round, so touching
-- available or damaged stock here would count those units a second time.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.approve_delivery(p_delivery_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_delivery RECORD;
  v_item RECORD;
  v_available INTEGER;
BEGIN
  IF public.current_role() != 'owner' THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT * INTO v_delivery FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF v_delivery IS NULL THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;
  IF v_delivery.approval_status != 'pending' THEN
    RAISE EXCEPTION 'delivery is already %', v_delivery.approval_status;
  END IF;
  IF v_delivery.loaded_at IS NOT NULL AND v_delivery.returns_recorded_at IS NULL THEN
    RAISE EXCEPTION 'this round is still out — the deliveryman has not recorded returns yet';
  END IF;

  FOR v_item IN
    SELECT di.delivered_quantity, dsi.product_id, dsi.unit_type
    FROM public.delivery_items di
    JOIN public.daily_summary_items dsi ON dsi.id = di.summary_item_id
    WHERE di.delivery_id = p_delivery_id AND di.delivered_quantity > 0
  LOOP
    SELECT available_qty INTO v_available FROM public.stock
      WHERE product_id = v_item.product_id AND unit_type = v_item.unit_type FOR UPDATE;
    IF v_available IS NULL OR v_available < v_item.delivered_quantity THEN
      RAISE EXCEPTION 'insufficient % stock for product %', v_item.unit_type, v_item.product_id;
    END IF;

    UPDATE public.stock
       SET available_qty = available_qty - v_item.delivered_quantity, updated_at = now()
     WHERE product_id = v_item.product_id AND unit_type = v_item.unit_type;
  END LOOP;

  UPDATE public.daily_summaries SET status = v_delivery.status, updated_at = now() WHERE id = v_delivery.summary_id;
  UPDATE public.deliveries
    SET approval_status = 'approved', approved_by = auth.uid(), approved_at = now()
    WHERE id = p_delivery_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.approve_delivery(UUID) TO authenticated;
