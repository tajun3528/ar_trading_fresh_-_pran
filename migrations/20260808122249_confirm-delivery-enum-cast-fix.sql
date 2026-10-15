-- Fix: a CASE expression with two untyped string-literal branches defaults to
-- `text`, so assigning it straight into an `order_status` column fails with
-- "column is of type order_status but expression is of type text". Cast each
-- branch explicitly.
CREATE OR REPLACE FUNCTION public.confirm_delivery(p_order_id UUID, p_items JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_order RECORD;
  v_route_id UUID;
  v_item JSONB;
  v_order_item RECORD;
  v_delivery_id UUID;
  v_delivered_qty INTEGER;
  v_pcs INTEGER;
  v_available INTEGER;
  v_payable NUMERIC(12,2) := 0;
  v_fully_delivered BOOLEAN := true;
  v_seen_items INTEGER := 0;
  v_status public.order_status;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF v_order IS NULL THEN
    RAISE EXCEPTION 'order not found';
  END IF;
  IF v_order.status NOT IN ('booked', 'partially_delivered') THEN
    RAISE EXCEPTION 'order is not deliverable';
  END IF;

  SELECT route_id INTO v_route_id FROM public.shops WHERE id = v_order.shop_id;
  IF NOT public.is_route_deliveryman(v_route_id) THEN
    RAISE EXCEPTION 'not your assigned route';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'delivery must contain at least one line item';
  END IF;

  INSERT INTO public.deliveries (order_id, deliveryman_id, delivery_datetime, status)
  VALUES (p_order_id, auth.uid(), now(), 'delivered')
  RETURNING id INTO v_delivery_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_order_item FROM public.order_items
      WHERE id = (v_item->>'order_item_id')::UUID AND order_id = p_order_id;
    IF v_order_item IS NULL THEN
      RAISE EXCEPTION 'order item not found on this order';
    END IF;
    v_seen_items := v_seen_items + 1;

    v_delivered_qty := (v_item->>'delivered_quantity')::INTEGER;
    IF v_delivered_qty IS NULL OR v_delivered_qty < 0 THEN
      RAISE EXCEPTION 'delivered quantity must not be negative';
    END IF;
    IF v_delivered_qty > v_order_item.quantity THEN
      RAISE EXCEPTION 'delivered quantity exceeds ordered quantity';
    END IF;
    IF v_delivered_qty < v_order_item.quantity THEN
      v_fully_delivered := false;
    END IF;

    v_pcs := public.to_pieces(v_order_item.product_id, v_order_item.unit_type, v_delivered_qty);

    SELECT available_pcs INTO v_available FROM public.stock
      WHERE product_id = v_order_item.product_id FOR UPDATE;
    IF v_available IS NULL OR v_available < v_pcs THEN
      RAISE EXCEPTION 'insufficient stock for product %', v_order_item.product_id;
    END IF;

    UPDATE public.stock SET available_pcs = available_pcs - v_pcs, updated_at = now()
      WHERE product_id = v_order_item.product_id;

    INSERT INTO public.delivery_items (delivery_id, order_item_id, delivered_quantity)
    VALUES (v_delivery_id, v_order_item.id, v_delivered_qty);

    v_payable := v_payable + (v_order_item.unit_price * v_delivered_qty);
  END LOOP;

  IF v_seen_items <> (SELECT count(*) FROM public.order_items WHERE order_id = p_order_id) THEN
    v_fully_delivered := false;
  END IF;

  v_status := CASE WHEN v_fully_delivered THEN 'delivered' ELSE 'partially_delivered' END::public.order_status;

  UPDATE public.deliveries SET status = v_status WHERE id = v_delivery_id;

  UPDATE public.orders SET
    status = v_status,
    payable_amount = v_payable,
    updated_at = now()
    WHERE id = p_order_id;

  RETURN v_delivery_id;
END;
$$;
