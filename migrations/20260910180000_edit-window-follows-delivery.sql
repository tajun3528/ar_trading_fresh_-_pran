-- ============================================================================
-- An order could only be edited while its delivery date was still in the
-- future. That rule predates back-dated orders: a day's selling written up
-- afterwards was locked the moment it was entered, and even a same-day order
-- became read-only, which is why the Edit button disappeared.
--
-- What actually makes an order unsafe to change is the van being loaded from
-- it — the delivery lines are built off the order's own lines at that point.
-- So the window now closes on the round starting, not on the calendar.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.edit_daily_summary(
  p_summary_id UUID,
  p_items JSONB,
  p_commission_amount NUMERIC DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_summary RECORD;
  v_item JSONB;
  v_total NUMERIC(12,2);
BEGIN
  SELECT * INTO v_summary FROM public.daily_summaries WHERE id = p_summary_id FOR UPDATE;
  IF v_summary IS NULL THEN
    RAISE EXCEPTION 'summary not found';
  END IF;
  IF v_summary.salesman_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'not your summary';
  END IF;
  IF v_summary.status <> 'booked' THEN
    RAISE EXCEPTION 'summary can no longer be edited';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.deliveries
     WHERE summary_id = p_summary_id AND approval_status <> 'rejected'
  ) THEN
    RAISE EXCEPTION 'the van has already been loaded for this order — ask the owner to reject the delivery report first';
  END IF;
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'summary must contain at least one line item';
  END IF;
  IF p_commission_amount IS NOT NULL AND p_commission_amount < 0 THEN
    RAISE EXCEPTION 'commission must not be negative';
  END IF;

  DELETE FROM public.daily_summary_items WHERE summary_id = p_summary_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    PERFORM public._apply_summary_item(
      p_summary_id,
      (v_item->>'product_id')::UUID,
      (v_item->>'unit_type')::public.unit_type,
      (v_item->>'quantity')::INTEGER,
      v_summary.company_id
    );
  END LOOP;

  SELECT COALESCE(SUM(line_total), 0) INTO v_total
    FROM public.daily_summary_items WHERE summary_id = p_summary_id;

  IF p_commission_amount IS NOT NULL AND p_commission_amount > v_total THEN
    RAISE EXCEPTION 'commission must not exceed the order total';
  END IF;

  UPDATE public.daily_summaries
     SET total_amount = v_total,
         commission_amount = COALESCE(p_commission_amount, commission_amount),
         updated_at = now()
   WHERE id = p_summary_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.edit_daily_summary(UUID, JSONB, NUMERIC) TO authenticated;
