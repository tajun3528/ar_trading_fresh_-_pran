-- ============================================================================
-- Salesmen collect payment on paper cash memos in the field and remit the
-- rest to the Owner after keeping their commission — commission_amount is a
-- fixed amount the salesman enters for that day's order, deducted from the
-- order total. Old signatures are dropped first: leaving them alongside the
-- new ones would make calls with fewer arguments ambiguous between
-- overloads.
-- ============================================================================
ALTER TABLE public.daily_summaries
  ADD COLUMN commission_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (commission_amount >= 0);

DROP FUNCTION IF EXISTS public.submit_daily_summary(JSONB, UUID, DATE);

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
  IF v_delivery_date <= current_date THEN
    RAISE EXCEPTION 'delivery date must be after today';
  END IF;

  IF p_route_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.routes WHERE id = p_route_id AND is_active
  ) THEN
    RAISE EXCEPTION 'route not found or inactive';
  END IF;

  SELECT id INTO v_summary_id
    FROM public.daily_summaries
    WHERE salesman_id = auth.uid() AND submission_date = current_date AND status = 'booked'
      AND route_id IS NOT DISTINCT FROM p_route_id
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

  SELECT COALESCE(SUM(line_total), 0) INTO v_total FROM public.daily_summary_items WHERE summary_id = v_summary_id;

  IF p_commission_amount IS NOT NULL AND p_commission_amount > v_total THEN
    RAISE EXCEPTION 'commission cannot exceed the order total of %', v_total;
  END IF;

  UPDATE public.daily_summaries
    SET total_amount = v_total,
        commission_amount = COALESCE(p_commission_amount, commission_amount),
        updated_at = now()
    WHERE id = v_summary_id;

  RETURN v_summary_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.submit_daily_summary(JSONB, UUID, DATE, NUMERIC) TO authenticated;

DROP FUNCTION IF EXISTS public.edit_daily_summary(UUID, JSONB);

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
  IF v_summary.status <> 'booked' OR v_summary.delivery_date <= current_date THEN
    RAISE EXCEPTION 'summary can no longer be edited';
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

  SELECT COALESCE(SUM(line_total), 0) INTO v_total FROM public.daily_summary_items WHERE summary_id = p_summary_id;

  IF p_commission_amount IS NOT NULL AND p_commission_amount > v_total THEN
    RAISE EXCEPTION 'commission cannot exceed the order total of %', v_total;
  END IF;

  UPDATE public.daily_summaries
    SET total_amount = v_total,
        commission_amount = COALESCE(p_commission_amount, commission_amount),
        updated_at = now()
    WHERE id = p_summary_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.edit_daily_summary(UUID, JSONB, NUMERIC) TO authenticated;
