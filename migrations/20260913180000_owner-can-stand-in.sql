-- ============================================================================
-- The owner can stand in for either role.
--
-- Until now the owner could only watch: orders came from salesmen and rounds
-- from delivery men, so if either was away the day simply went unrecorded.
-- Now the owner can book an order on a salesman's behalf, and run or finish a
-- delivery round when the delivery man cannot.
--
-- Deliberately NOT a separate "owner mode": an owner-booked order is an
-- ordinary order belonging to the salesman named on it, and an owner-run
-- round belongs to that salesman's delivery man. Everything downstream --
-- pricing, commission, stock, profit, notifications -- keeps working without
-- knowing the owner was involved. The audit log records who really acted.
--
-- The bodies below are the live definitions with only their permission checks
-- changed, taken straight from the database so the money logic is unaltered.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.submit_daily_summary(p_items jsonb, p_route_id uuid DEFAULT NULL::uuid, p_delivery_date date DEFAULT NULL::date, p_commission_amount numeric DEFAULT NULL::numeric, p_salesman_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  v_summary_id UUID;
  v_item JSONB;
  v_total NUMERIC(12,2);
  v_company_id UUID;
  v_salesman_id UUID;
  v_delivery_date DATE;
BEGIN
  -- The owner may book on a salesman's behalf. The order is then the
  -- salesman's in every respect: their monthly selling prices, their
  -- commission, their line in Salesmen & Routes. The company follows from the
  -- salesman, since a salesman only ever sells one company's catalog.
  IF public.current_role() = 'owner' THEN
    IF p_salesman_id IS NULL THEN
      RAISE EXCEPTION 'choose which salesman this order belongs to';
    END IF;
    SELECT company_id INTO v_company_id
      FROM public.profiles
     WHERE user_id = p_salesman_id AND role = 'salesman' AND status = 'active';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'that salesman is not active';
    END IF;
    v_salesman_id := p_salesman_id;
  ELSE
    IF public.current_role() IS DISTINCT FROM 'salesman' OR public.current_status() IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION 'only an active salesman can submit a daily summary';
    END IF;
    IF p_salesman_id IS NOT NULL AND p_salesman_id <> auth.uid() THEN
      RAISE EXCEPTION 'you can only book your own orders';
    END IF;
    v_company_id := public.current_company_id();
    v_salesman_id := auth.uid();
  END IF;
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'you are not assigned to a company yet â€” ask the owner to assign one';
  END IF;
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'summary must contain at least one line item';
  END IF;
  IF p_commission_amount IS NOT NULL AND p_commission_amount < 0 THEN
    RAISE EXCEPTION 'commission must not be negative';
  END IF;

  v_delivery_date := COALESCE(p_delivery_date, current_date + 1);

  IF p_route_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.routes WHERE id = p_route_id AND is_active
  ) THEN
    RAISE EXCEPTION 'route not found or inactive';
  END IF;

  -- Same salesman, same delivery day, same route, still open: one order.
  SELECT id INTO v_summary_id
    FROM public.daily_summaries
    WHERE salesman_id = v_salesman_id
      AND delivery_date = v_delivery_date
      AND route_id IS NOT DISTINCT FROM p_route_id
      AND status = 'booked'
    ORDER BY created_at
    LIMIT 1
    FOR UPDATE;

  IF v_summary_id IS NULL THEN
    INSERT INTO public.daily_summaries (
      salesman_id, submission_date, delivery_date, total_amount, status, company_id, route_id, commission_amount
    )
    VALUES (v_salesman_id, current_date, v_delivery_date, 0, 'booked', v_company_id, p_route_id, COALESCE(p_commission_amount, 0))
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

  SELECT COALESCE(SUM(line_total), 0) INTO v_total
    FROM public.daily_summary_items WHERE summary_id = v_summary_id;

  IF p_commission_amount IS NOT NULL AND p_commission_amount > v_total THEN
    RAISE EXCEPTION 'commission must not exceed the order total';
  END IF;

  UPDATE public.daily_summaries
     SET total_amount = v_total,
         commission_amount = COALESCE(p_commission_amount, commission_amount)
   WHERE id = v_summary_id;

  RETURN v_summary_id;
END;
$function$;


CREATE OR REPLACE FUNCTION public.load_delivery_van(p_summary_id uuid, p_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  v_summary RECORD;
  v_item JSONB;
  v_summary_item RECORD;
  v_delivery_id UUID;
  v_loaded INTEGER;
  v_any_loaded BOOLEAN := false;
BEGIN
  SELECT * INTO v_summary FROM public.daily_summaries WHERE id = p_summary_id FOR UPDATE;
  IF v_summary IS NULL THEN
    RAISE EXCEPTION 'summary not found';
  END IF;
  IF v_summary.status NOT IN ('booked', 'partially_delivered') THEN
    RAISE EXCEPTION 'summary is not deliverable';
  END IF;
  -- The owner can run the round themselves when the delivery man is away.
  IF public.current_role() <> 'owner'
     AND NOT public.is_paired_deliveryman(v_summary.salesman_id) THEN
    RAISE EXCEPTION 'not your paired salesman';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.deliveries WHERE summary_id = p_summary_id AND approval_status = 'pending'
  ) THEN
    RAISE EXCEPTION 'this order already has a delivery in progress or waiting on owner approval';
  END IF;

  INSERT INTO public.deliveries (summary_id, deliveryman_id, delivery_datetime, status, approval_status, loaded_at)
  VALUES (
    p_summary_id,
    -- Owner standing in: the round still belongs to the salesman's own
    -- delivery man so his history stays continuous. Who actually pressed the
    -- button is recorded in the audit log either way.
    CASE WHEN public.current_role() = 'owner'
         THEN COALESCE(
                (SELECT paired_deliveryman_id FROM public.profiles WHERE user_id = v_summary.salesman_id),
                auth.uid())
         ELSE auth.uid() END,
    now(), 'booked', 'pending', now())
  RETURNING id INTO v_delivery_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_summary_item FROM public.daily_summary_items
      WHERE id = (v_item->>'summary_item_id')::UUID AND summary_id = p_summary_id;
    IF v_summary_item IS NULL THEN
      RAISE EXCEPTION 'summary item not found on this summary';
    END IF;

    v_loaded := COALESCE((v_item->>'loaded_quantity')::INTEGER, 0);
    IF v_loaded < 0 OR v_loaded > v_summary_item.quantity THEN
      RAISE EXCEPTION 'loaded quantity must be between 0 and the ordered quantity';
    END IF;
    IF v_loaded > 0 THEN
      v_any_loaded := true;
    END IF;

    INSERT INTO public.delivery_items (delivery_id, summary_item_id, loaded_quantity, delivered_quantity)
    VALUES (v_delivery_id, v_summary_item.id, v_loaded, 0);
  END LOOP;

  IF NOT v_any_loaded THEN
    RAISE EXCEPTION 'tick at least one product as loaded into the van';
  END IF;

  RETURN v_delivery_id;
END;
$function$;


CREATE OR REPLACE FUNCTION public.close_delivery_round(p_delivery_id uuid, p_items jsonb, p_damages jsonb DEFAULT '[]'::jsonb)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
  -- The owner can finish a round the delivery man could not.
  IF v_delivery.deliveryman_id <> auth.uid() AND public.current_role() <> 'owner' THEN
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
$function$;


CREATE OR REPLACE FUNCTION public.add_delivery_line(p_delivery_id uuid, p_product_id uuid, p_unit_type unit_type, p_quantity integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
DECLARE
  v_delivery RECORD;
  v_summary RECORD;
  v_product RECORD;
  v_item_id UUID;
  v_total NUMERIC(12,2);
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be more than zero';
  END IF;

  SELECT * INTO v_delivery FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF v_delivery IS NULL THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;
  -- The owner can finish a round the delivery man could not.
  IF v_delivery.deliveryman_id <> auth.uid() AND public.current_role() <> 'owner' THEN
    RAISE EXCEPTION 'not your delivery';
  END IF;
  IF v_delivery.loaded_at IS NULL THEN
    RAISE EXCEPTION 'load the van before adding products to the round';
  END IF;
  IF v_delivery.returns_recorded_at IS NOT NULL THEN
    RAISE EXCEPTION 'this round is already closed and waiting on owner approval';
  END IF;

  SELECT * INTO v_summary FROM public.daily_summaries WHERE id = v_delivery.summary_id FOR UPDATE;

  -- Only this company's catalog: a round must never mix two vendors' goods.
  SELECT id, name, company_id INTO v_product FROM public.products WHERE id = p_product_id;
  IF v_product IS NULL THEN
    RAISE EXCEPTION 'product not found';
  END IF;
  IF v_product.company_id IS DISTINCT FROM v_summary.company_id THEN
    RAISE EXCEPTION 'that product belongs to a different company';
  END IF;

  -- Prices and rolls up cartons exactly as a salesman's own line would.
  PERFORM public._apply_summary_item(
    v_delivery.summary_id, p_product_id, p_unit_type, p_quantity, v_summary.company_id);

  SELECT id INTO v_item_id
    FROM public.daily_summary_items
   WHERE summary_id = v_delivery.summary_id
     AND product_id = p_product_id
     AND unit_type = p_unit_type;

  -- The goods leave the van now, so the line counts as loaded. If the product
  -- was already on the round, top up what went out rather than duplicating it.
  INSERT INTO public.delivery_items (
    delivery_id, summary_item_id, loaded_quantity, delivered_quantity,
    returned_quantity, damaged_quantity, added_by_deliveryman)
  VALUES (p_delivery_id, v_item_id, p_quantity, 0, 0, 0, true)
  ON CONFLICT (delivery_id, summary_item_id) DO UPDATE
    SET loaded_quantity = public.delivery_items.loaded_quantity + EXCLUDED.loaded_quantity,
        added_by_deliveryman = true;

  SELECT COALESCE(SUM(line_total), 0) INTO v_total
    FROM public.daily_summary_items WHERE summary_id = v_delivery.summary_id;
  UPDATE public.daily_summaries
     SET total_amount = v_total, updated_at = now()
   WHERE id = v_delivery.summary_id;

  RETURN v_item_id;
END;
$function$;
