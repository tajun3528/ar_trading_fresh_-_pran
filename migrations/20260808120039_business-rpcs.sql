-- ============================================================================
-- book_order — FR-6: next-day booking only, price locked at booking time,
-- restricted to the shop's assigned salesman.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.book_order(p_shop_id UUID, p_items JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_route_id UUID;
  v_order_id UUID;
  v_item JSONB;
  v_unit_price NUMERIC(12,2);
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_qty INTEGER;
  v_unit public.unit_type;
  v_product_id UUID;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'salesman' OR public.current_status() IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'only an active salesman can book orders';
  END IF;

  SELECT route_id INTO v_route_id FROM public.shops WHERE id = p_shop_id AND is_active;
  IF v_route_id IS NULL THEN
    RAISE EXCEPTION 'shop not found or inactive';
  END IF;
  IF NOT public.is_route_salesman(v_route_id) THEN
    RAISE EXCEPTION 'shop is not on your assigned route';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'order must contain at least one line item';
  END IF;

  INSERT INTO public.orders (shop_id, salesman_id, booking_date, delivery_date, total_amount, payable_amount, status)
  VALUES (p_shop_id, auth.uid(), current_date, current_date + 1, 0, 0, 'booked')
  RETURNING id INTO v_order_id;

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

    INSERT INTO public.order_items (order_id, product_id, unit_type, quantity, unit_price, line_total)
    VALUES (v_order_id, v_product_id, v_unit, v_qty, v_unit_price, v_line_total);
  END LOOP;

  UPDATE public.orders SET total_amount = v_total, payable_amount = v_total, updated_at = now()
    WHERE id = v_order_id;

  RETURN v_order_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.book_order(UUID, JSONB) TO authenticated;

-- ============================================================================
-- edit_order / cancel_order — FR-6.7: only before the delivery day begins.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.edit_order(p_order_id UUID, p_items JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_order RECORD;
  v_item JSONB;
  v_unit_price NUMERIC(12,2);
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_qty INTEGER;
  v_unit public.unit_type;
  v_product_id UUID;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF v_order IS NULL THEN
    RAISE EXCEPTION 'order not found';
  END IF;
  IF v_order.salesman_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'not your order';
  END IF;
  IF v_order.status <> 'booked' OR v_order.delivery_date <= current_date THEN
    RAISE EXCEPTION 'order can no longer be edited';
  END IF;
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'order must contain at least one line item';
  END IF;

  DELETE FROM public.order_items WHERE order_id = p_order_id;

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

    INSERT INTO public.order_items (order_id, product_id, unit_type, quantity, unit_price, line_total)
    VALUES (p_order_id, v_product_id, v_unit, v_qty, v_unit_price, v_line_total);
  END LOOP;

  UPDATE public.orders SET total_amount = v_total, payable_amount = v_total, updated_at = now()
    WHERE id = p_order_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.edit_order(UUID, JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_order(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_order RECORD;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF v_order IS NULL THEN
    RAISE EXCEPTION 'order not found';
  END IF;
  IF v_order.salesman_id IS DISTINCT FROM auth.uid() AND public.current_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF v_order.status <> 'booked' OR v_order.delivery_date <= current_date THEN
    RAISE EXCEPTION 'order can no longer be cancelled';
  END IF;

  UPDATE public.orders SET status = 'cancelled', updated_at = now() WHERE id = p_order_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cancel_order(UUID) TO authenticated;

-- ============================================================================
-- confirm_delivery — FR-7: full or partial delivery, decrements stock,
-- never lets stock go negative (NFR-5).
-- p_items: [{"order_item_id": "...", "delivered_quantity": N}, ...]
-- ============================================================================
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

  UPDATE public.deliveries
    SET status = CASE WHEN v_fully_delivered THEN 'delivered' ELSE 'partially_delivered' END
    WHERE id = v_delivery_id;

  UPDATE public.orders SET
    status = CASE WHEN v_fully_delivered THEN 'delivered' ELSE 'partially_delivered' END,
    payable_amount = v_payable,
    updated_at = now()
    WHERE id = p_order_id;

  RETURN v_delivery_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.confirm_delivery(UUID, JSONB) TO authenticated;

-- ============================================================================
-- record_return — FR-8: good stock goes back to available, damaged goes to
-- the damaged bucket; adjusts payable_amount if tied to a delivered order.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.record_return(
  p_shop_id UUID,
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_quantity INTEGER,
  p_condition public.return_condition,
  p_reason TEXT,
  p_order_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_route_id UUID;
  v_return_id UUID;
  v_pcs INTEGER;
  v_line_value NUMERIC(12,2);
BEGIN
  IF public.current_role() NOT IN ('owner', 'deliveryman') THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be positive';
  END IF;

  SELECT route_id INTO v_route_id FROM public.shops WHERE id = p_shop_id;
  IF v_route_id IS NULL THEN
    RAISE EXCEPTION 'shop not found';
  END IF;
  IF public.current_role() = 'deliveryman' AND NOT public.is_route_deliveryman(v_route_id) THEN
    RAISE EXCEPTION 'not your assigned route';
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

  INSERT INTO public.returns (shop_id, order_id, product_id, unit_type, quantity, condition, reason, return_date, recorded_by)
  VALUES (p_shop_id, p_order_id, p_product_id, p_unit_type, p_quantity, p_condition, p_reason, current_date, auth.uid())
  RETURNING id INTO v_return_id;

  IF p_order_id IS NOT NULL THEN
    SELECT unit_price * p_quantity INTO v_line_value
      FROM public.order_items
      WHERE order_id = p_order_id AND product_id = p_product_id AND unit_type = p_unit_type
      LIMIT 1;
    IF v_line_value IS NOT NULL THEN
      UPDATE public.orders SET payable_amount = GREATEST(payable_amount - v_line_value, 0), updated_at = now()
        WHERE id = p_order_id;
    END IF;
  END IF;

  RETURN v_return_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.record_return(UUID, UUID, public.unit_type, INTEGER, public.return_condition, TEXT, UUID) TO authenticated;

-- ============================================================================
-- record_payment — FR-9: never allow payment beyond the outstanding due.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.record_payment(p_order_id UUID, p_amount NUMERIC)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_order RECORD;
  v_route_id UUID;
  v_paid NUMERIC(12,2);
  v_due NUMERIC(12,2);
  v_payment_id UUID;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'amount must be positive';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF v_order IS NULL THEN
    RAISE EXCEPTION 'order not found';
  END IF;

  SELECT route_id INTO v_route_id FROM public.shops WHERE id = v_order.shop_id;
  IF public.current_role() = 'deliveryman' THEN
    IF NOT public.is_route_deliveryman(v_route_id) THEN
      RAISE EXCEPTION 'not your assigned route';
    END IF;
  ELSIF public.current_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_paid FROM public.payments WHERE order_id = p_order_id;
  v_due := v_order.payable_amount - v_paid;

  IF p_amount > v_due THEN
    RAISE EXCEPTION 'payment amount exceeds outstanding due of %', v_due;
  END IF;

  INSERT INTO public.payments (order_id, shop_id, amount, payment_date, collected_by)
  VALUES (p_order_id, v_order.shop_id, p_amount, current_date, auth.uid())
  RETURNING id INTO v_payment_id;

  RETURN v_payment_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.record_payment(UUID, NUMERIC) TO authenticated;

-- ============================================================================
-- stock_in — FR-5.1/5.2: owner-only, converts to pieces and tops up available.
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
  v_pcs INTEGER;
  v_id UUID;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'only the owner can record stock-in';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be positive';
  END IF;

  v_pcs := public.to_pieces(p_product_id, p_unit_type, p_quantity);
  IF v_pcs IS NULL THEN
    RAISE EXCEPTION 'product not found';
  END IF;

  INSERT INTO public.stock_ins (product_id, unit_type, quantity, total_pcs, entry_date, entered_by)
  VALUES (p_product_id, p_unit_type, p_quantity, v_pcs, p_entry_date, auth.uid())
  RETURNING id INTO v_id;

  UPDATE public.stock SET available_pcs = available_pcs + v_pcs, updated_at = now()
    WHERE product_id = p_product_id;

  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.stock_in(UUID, public.unit_type, INTEGER, DATE) TO authenticated;

-- ============================================================================
-- resolve_login_email — lets the login screen accept a mobile number or an
-- email and resolve it to the real auth email before calling /api/auth/sessions.
-- Granted to anon since it runs pre-authentication.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.resolve_login_email(p_identifier TEXT)
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT au.email FROM auth.users au
    JOIN public.profiles p ON p.user_id = au.id
    WHERE p.mobile = p_identifier OR au.email = p_identifier
    LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.resolve_login_email(TEXT) TO anon, authenticated;
