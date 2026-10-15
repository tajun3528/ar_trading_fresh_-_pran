-- ============================================================================
-- Orders can now carry any delivery date, including past ones, so a day's
-- selling that was written on paper can be entered afterwards. The delivery
-- side never had a date restriction, so a back-dated order can be marked
-- delivered as normal.
--
-- submission_date still records when the entry was actually made — that is
-- the honest audit trail — while delivery_date carries the day the goods
-- moved. Profit is reported on the delivery month, so a back-dated order
-- lands in the month it belongs to.
--
-- The same-day merge key gains delivery_date: two summaries entered today for
-- the same route but different past days are different orders and must not
-- collapse into one, while two entries for the same route and same delivery
-- day still merge as before.
-- ============================================================================
DROP FUNCTION IF EXISTS public.submit_daily_summary(JSONB, UUID, DATE, NUMERIC);

CREATE OR REPLACE FUNCTION public.submit_daily_summary(
  p_items JSONB,
  p_route_id UUID DEFAULT NULL,
  p_delivery_date DATE DEFAULT NULL,
  p_commission_amount NUMERIC DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_summary_id UUID;
  v_item JSONB;
  v_total NUMERIC(12,2);
  v_company_id UUID;
  v_delivery_date DATE;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'salesman' OR public.current_status() IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'only an active salesman can submit a daily summary';
  END IF;
  v_company_id := public.current_company_id();
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'you are not assigned to a company yet — ask the owner to assign one';
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

  SELECT id INTO v_summary_id
    FROM public.daily_summaries
    WHERE salesman_id = auth.uid() AND submission_date = current_date AND status = 'booked'
      AND route_id IS NOT DISTINCT FROM p_route_id
      AND delivery_date = v_delivery_date
    FOR UPDATE;

  IF v_summary_id IS NULL THEN
    INSERT INTO public.daily_summaries (
      salesman_id, submission_date, delivery_date, total_amount, status, company_id, route_id, commission_amount
    )
    VALUES (auth.uid(), current_date, v_delivery_date, 0, 'booked', v_company_id, p_route_id, COALESCE(p_commission_amount, 0))
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
$$;

GRANT EXECUTE ON FUNCTION public.submit_daily_summary(JSONB, UUID, DATE, NUMERIC) TO authenticated;
