-- ============================================================================
-- One-time correction: the 10 Sep order was entered for the wrong day. It
-- belongs with the 9 Sep order for the same salesman and route, so it moves
-- back a day and the two become the single order they were meant to be.
--
--   9 Sep   ৳21,393.00  (commission ৳170)
--   10 Sep     ৳620.00  — Choc Wafer box x1, Milk Wafer box x3
--   merged  ৳22,013.00
--
-- Milk Wafer box is on both at the same ৳155, so those lines add: 3 + 3 = 6.
-- Boxes have no carton rollup, so no split has to be recomputed.
--
-- Neither order has a delivery against it, which is what makes this safe —
-- the guard below refuses to run if that has changed since.
-- ============================================================================
DO $$
DECLARE
  v_keep UUID := 'abbe090f-0dd2-4f85-996c-bb8a8c3a1c0f';  -- 9 Sep
  v_drop UUID := '62d37769-a0fc-4308-a06d-d06bf3511787';  -- 10 Sep
  v_line RECORD;
  v_existing_id UUID;
  v_total NUMERIC(12,2);
  v_commission NUMERIC(12,2);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.daily_summaries WHERE id = v_keep AND delivery_date = DATE '2026-09-09')
     OR NOT EXISTS (SELECT 1 FROM public.daily_summaries WHERE id = v_drop AND delivery_date = DATE '2026-09-10') THEN
    RAISE EXCEPTION 'the two orders are not in the expected state — not merging';
  END IF;

  IF EXISTS (SELECT 1 FROM public.deliveries WHERE summary_id IN (v_keep, v_drop)) THEN
    RAISE EXCEPTION 'a delivery now exists against one of these orders — not merging';
  END IF;

  SELECT COALESCE(SUM(commission_amount), 0) INTO v_commission
    FROM public.daily_summaries WHERE id IN (v_keep, v_drop);

  FOR v_line IN
    SELECT * FROM public.daily_summary_items WHERE summary_id = v_drop
  LOOP
    SELECT id INTO v_existing_id
      FROM public.daily_summary_items
     WHERE summary_id = v_keep
       AND product_id = v_line.product_id
       AND unit_type = v_line.unit_type
     FOR UPDATE;

    IF v_existing_id IS NULL THEN
      UPDATE public.daily_summary_items SET summary_id = v_keep WHERE id = v_line.id;
    ELSE
      UPDATE public.daily_summary_items
         SET quantity = quantity + v_line.quantity,
             line_total = unit_price * (quantity + v_line.quantity)
       WHERE id = v_existing_id;
      DELETE FROM public.daily_summary_items WHERE id = v_line.id;
    END IF;
  END LOOP;

  SELECT COALESCE(SUM(line_total), 0) INTO v_total
    FROM public.daily_summary_items WHERE summary_id = v_keep;

  UPDATE public.daily_summaries
     SET total_amount = v_total,
         commission_amount = v_commission,
         updated_at = now()
   WHERE id = v_keep;

  DELETE FROM public.daily_summaries WHERE id = v_drop;

  IF v_total <> 22013.00 THEN
    RAISE EXCEPTION 'merged total came to %, expected 22013.00 — rolling back', v_total;
  END IF;
END $$;
