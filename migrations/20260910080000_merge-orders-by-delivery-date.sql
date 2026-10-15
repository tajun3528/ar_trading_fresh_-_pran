-- ============================================================================
-- Orders for the same delivery day now merge into one, regardless of which
-- day they were entered.
--
-- The merge key was keyed on submission_date, so an order entered today and
-- another entered tomorrow — both for the same delivery day and route —
-- became two separate orders. Now that a delivery date can be back-dated,
-- that split shows up routinely: enter part of Monday's selling on Monday,
-- the rest on Tuesday, and you had two Monday orders instead of one.
--
-- Route stays in the key. Routes exist precisely so a day's selling in
-- Monipur Bazar and in Hotapara stay separate rather than collapsing into
-- one figure.
--
-- Also fixes the name of "Fresh Crispee Coco Wafer-Jar 20G (4X20" — its
-- closing bracket was missing.
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

  -- Same salesman, same delivery day, same route, still open: one order.
  SELECT id INTO v_summary_id
    FROM public.daily_summaries
    WHERE salesman_id = auth.uid()
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

UPDATE public.products
   SET name = 'Fresh Crispee Coco Wafer-Jar 20G (4X20)'
 WHERE name = 'Fresh Crispee Coco Wafer-Jar 20G (4X20';
