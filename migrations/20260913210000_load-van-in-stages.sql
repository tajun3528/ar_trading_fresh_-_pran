-- ============================================================================
-- Loading the van in more than one go.
--
-- A big order does not always fit. The van was loaded once, in a single pass,
-- and the round then moved straight on to returns -- so a second trip to the
-- warehouse for the same order had nowhere to be recorded, and the quantities
-- on the round were wrong for the rest of the day.
--
-- Now the load can be topped up as many times as it takes while the round is
-- still open. It stays one round with one cash settlement and one approval at
-- the end; only the loading happens in stages.
--
-- The ordered quantity is also no longer a ceiling, so the van can carry
-- buffer stock. That is safe because loading moves no stock by itself:
-- approve_delivery deducts only delivered_quantity, and goods that come back
-- were never taken out of the warehouse count in the first place.
-- ============================================================================

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
    -- No upper limit: the van may carry more than the order as buffer, which
    -- a shop can then buy through add_delivery_line. Loading moves no stock
    -- on its own -- approval deducts only what was actually delivered -- so
    -- carrying extra and bringing it back cannot distort the warehouse count.
    IF v_loaded < 0 THEN
      RAISE EXCEPTION 'loaded quantity cannot be negative';
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


-- ============================================================================
-- load_more_into_van -- a second (or third) load onto a round already open.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.load_more_into_van(p_delivery_id UUID, p_items JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $fn$
DECLARE
  v_delivery RECORD;
  v_item JSONB;
  v_summary_item RECORD;
  v_extra INTEGER;
  v_any BOOLEAN := false;
BEGIN
  SELECT * INTO v_delivery FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF v_delivery IS NULL THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;
  IF v_delivery.deliveryman_id <> auth.uid() AND public.current_role() <> 'owner' THEN
    RAISE EXCEPTION 'not your delivery';
  END IF;
  IF v_delivery.loaded_at IS NULL THEN
    RAISE EXCEPTION 'load the van first';
  END IF;
  IF v_delivery.returns_recorded_at IS NOT NULL THEN
    RAISE EXCEPTION 'this round is already closed and waiting on owner approval';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) LOOP
    SELECT * INTO v_summary_item FROM public.daily_summary_items
      WHERE id = (v_item->>'summary_item_id')::UUID AND summary_id = v_delivery.summary_id;
    IF v_summary_item IS NULL THEN
      RAISE EXCEPTION 'that product is not on this order';
    END IF;

    -- What is being ADDED to the van now, not the new running total, so two
    -- people topping up at once cannot overwrite each other.
    v_extra := COALESCE((v_item->>'add_quantity')::INTEGER, 0);
    IF v_extra < 0 THEN
      RAISE EXCEPTION 'quantity to add cannot be negative';
    END IF;
    CONTINUE WHEN v_extra = 0;
    v_any := true;

    INSERT INTO public.delivery_items (
      delivery_id, summary_item_id, loaded_quantity, delivered_quantity,
      returned_quantity, damaged_quantity)
    VALUES (p_delivery_id, v_summary_item.id, v_extra, 0, 0, 0)
    ON CONFLICT (delivery_id, summary_item_id) DO UPDATE
      SET loaded_quantity = public.delivery_items.loaded_quantity + EXCLUDED.loaded_quantity;
  END LOOP;

  IF NOT v_any THEN
    RAISE EXCEPTION 'enter a quantity for at least one product';
  END IF;

  UPDATE public.deliveries SET loaded_at = now() WHERE id = p_delivery_id;
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.load_more_into_van(UUID, JSONB) TO authenticated;
