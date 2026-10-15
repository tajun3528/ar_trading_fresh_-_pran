-- ============================================================================
-- submit_daily_summary — salesman's aggregate "what's needed for tomorrow"
-- submission. No shop reference: shop-level dealing stays on paper cash memos.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.submit_daily_summary(p_items JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_summary_id UUID;
  v_item JSONB;
  v_unit_price NUMERIC(12,2);
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_qty INTEGER;
  v_unit public.unit_type;
  v_product_id UUID;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'salesman' OR public.current_status() IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'only an active salesman can submit a daily summary';
  END IF;
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'summary must contain at least one line item';
  END IF;

  INSERT INTO public.daily_summaries (salesman_id, submission_date, delivery_date, total_amount, status)
  VALUES (auth.uid(), current_date, current_date + 1, 0, 'booked')
  RETURNING id INTO v_summary_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_product_id := (v_item->>'product_id')::UUID;
    v_unit := (v_item->>'unit_type')::public.unit_type;
    v_qty := (v_item->>'quantity')::INTEGER;
    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'quantity must be positive';
    END IF;

    SELECT pu.price INTO v_unit_price
      FROM public.product_units pu
      JOIN public.products p ON p.id = pu.product_id
      WHERE pu.product_id = v_product_id AND pu.unit_type = v_unit AND p.is_active;
    IF v_unit_price IS NULL THEN
      RAISE EXCEPTION 'no active price for the given product/unit';
    END IF;

    v_line_total := v_unit_price * v_qty;
    v_total := v_total + v_line_total;

    INSERT INTO public.daily_summary_items (summary_id, product_id, unit_type, quantity, unit_price, line_total)
    VALUES (v_summary_id, v_product_id, v_unit, v_qty, v_unit_price, v_line_total);
  END LOOP;

  UPDATE public.daily_summaries SET total_amount = v_total, updated_at = now() WHERE id = v_summary_id;

  RETURN v_summary_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.submit_daily_summary(JSONB) TO authenticated;

-- ============================================================================
-- edit_daily_summary / cancel_daily_summary — only before the delivery day
-- begins, only by the submitting salesman.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.edit_daily_summary(p_summary_id UUID, p_items JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_summary RECORD;
  v_item JSONB;
  v_unit_price NUMERIC(12,2);
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_qty INTEGER;
  v_unit public.unit_type;
  v_product_id UUID;
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
    v_product_id := (v_item->>'product_id')::UUID;
    v_unit := (v_item->>'unit_type')::public.unit_type;
    v_qty := (v_item->>'quantity')::INTEGER;
    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'quantity must be positive';
    END IF;

    SELECT pu.price INTO v_unit_price
      FROM public.product_units pu
      JOIN public.products p ON p.id = pu.product_id
      WHERE pu.product_id = v_product_id AND pu.unit_type = v_unit AND p.is_active;
    IF v_unit_price IS NULL THEN
      RAISE EXCEPTION 'no active price for the given product/unit';
    END IF;

    v_line_total := v_unit_price * v_qty;
    v_total := v_total + v_line_total;

    INSERT INTO public.daily_summary_items (summary_id, product_id, unit_type, quantity, unit_price, line_total)
    VALUES (p_summary_id, v_product_id, v_unit, v_qty, v_unit_price, v_line_total);
  END LOOP;

  UPDATE public.daily_summaries SET total_amount = v_total, updated_at = now() WHERE id = p_summary_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.edit_daily_summary(UUID, JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_daily_summary(p_summary_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_summary RECORD;
BEGIN
  SELECT * INTO v_summary FROM public.daily_summaries WHERE id = p_summary_id FOR UPDATE;
  IF v_summary IS NULL THEN
    RAISE EXCEPTION 'summary not found';
  END IF;
  IF v_summary.salesman_id IS DISTINCT FROM auth.uid() AND public.current_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF v_summary.status <> 'booked' OR v_summary.delivery_date <= current_date THEN
    RAISE EXCEPTION 'summary can no longer be cancelled';
  END IF;

  UPDATE public.daily_summaries SET status = 'cancelled', updated_at = now() WHERE id = p_summary_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cancel_daily_summary(UUID) TO authenticated;

-- ============================================================================
-- confirm_summary_delivery — the paired delivery man confirms actual
-- delivered quantities (full or partial), decrementing stock (never negative).
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
  v_pcs INTEGER;
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

    v_pcs := public.to_pieces(v_summary_item.product_id, v_summary_item.unit_type, v_delivered_qty);

    SELECT available_pcs INTO v_available FROM public.stock
      WHERE product_id = v_summary_item.product_id FOR UPDATE;
    IF v_available IS NULL OR v_available < v_pcs THEN
      RAISE EXCEPTION 'insufficient stock for product %', v_summary_item.product_id;
    END IF;

    UPDATE public.stock SET available_pcs = available_pcs - v_pcs, updated_at = now()
      WHERE product_id = v_summary_item.product_id;

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
GRANT EXECUTE ON FUNCTION public.confirm_summary_delivery(UUID, JSONB) TO authenticated;

-- ============================================================================
-- record_return — standalone field event (no shop/order/payable linkage).
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
  v_pcs INTEGER;
  v_return_id UUID;
BEGIN
  IF public.current_role() NOT IN ('owner', 'deliveryman') THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be positive';
  END IF;

  v_pcs := public.to_pieces(p_product_id, p_unit_type, p_quantity);
  IF v_pcs IS NULL THEN
    RAISE EXCEPTION 'product not found';
  END IF;

  IF p_condition = 'good' THEN
    UPDATE public.stock SET available_pcs = available_pcs + v_pcs, updated_at = now()
      WHERE product_id = p_product_id;
  ELSE
    UPDATE public.stock SET damaged_pcs = damaged_pcs + v_pcs, updated_at = now()
      WHERE product_id = p_product_id;
  END IF;

  INSERT INTO public.returns (product_id, unit_type, quantity, condition, reason, return_date, recorded_by)
  VALUES (p_product_id, p_unit_type, p_quantity, p_condition, p_reason, current_date, auth.uid())
  RETURNING id INTO v_return_id;

  RETURN v_return_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.record_return(UUID, public.unit_type, INTEGER, public.return_condition, TEXT) TO authenticated;
