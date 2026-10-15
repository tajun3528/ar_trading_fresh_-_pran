-- ============================================================================
-- The Monipur Bazar order (৳43,332, submitted 10 Sep) was entered for
-- delivery on 11 Sep and belongs on the 10th.
--
-- Safe to move: no delivery has been filed against it, and the only other
-- order is Vobanipur Bazar's, so there is nothing on the 10th for this
-- salesman and route to collide with.
--
-- Delivery date is what profit is reported on, so this also moves the order
-- into the month-to-date figures for the 10th rather than the 11th.
-- ============================================================================
DO $$
DECLARE
  v_id UUID := '13bce078-dc73-43c5-a497-894eaac075d9';
  v_route UUID;
  v_salesman UUID;
BEGIN
  SELECT route_id, salesman_id INTO v_route, v_salesman
    FROM public.daily_summaries WHERE id = v_id AND delivery_date = DATE '2026-09-11';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'that order is no longer dated 11 Sep — not moving it';
  END IF;

  IF EXISTS (SELECT 1 FROM public.deliveries WHERE summary_id = v_id) THEN
    RAISE EXCEPTION 'a delivery has been filed against this order — not moving its date';
  END IF;

  -- Another order for the same salesman, route and day would have to be
  -- merged rather than left sitting alongside this one.
  IF EXISTS (
    SELECT 1 FROM public.daily_summaries
     WHERE id <> v_id
       AND salesman_id = v_salesman
       AND route_id IS NOT DISTINCT FROM v_route
       AND delivery_date = DATE '2026-09-10'
       AND status = 'booked'
  ) THEN
    RAISE EXCEPTION 'an order already exists for that salesman, route and day — merge instead';
  END IF;

  UPDATE public.daily_summaries
     SET delivery_date = DATE '2026-09-10', updated_at = now()
   WHERE id = v_id;
END $$;
