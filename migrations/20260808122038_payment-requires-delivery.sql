-- Fix: record_payment allowed collecting payment against an order that had
-- not been delivered yet (payable_amount is pre-populated at booking time so
-- the due-check alone didn't catch this). FR-9.1/9.2 tie payment to delivered
-- orders — a delivery man collects payment while delivering, not before.
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
  IF v_order.status NOT IN ('delivered', 'partially_delivered') THEN
    RAISE EXCEPTION 'order has not been delivered yet';
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
