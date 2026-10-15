-- ============================================================================
-- submit_daily_summary previously inserted a new daily_summaries row on
-- every call, so a salesman submitting more than once in a day ended up with
-- multiple separate "orders" for the same delivery date. Now: if the
-- salesman already has a booked summary for today, new items merge into it
-- (matching product+unit lines add quantity together; new ones append) —
-- one order per salesman per day, regardless of how many times they submit.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.submit_daily_summary(p_items JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_summary_id UUID;
  v_item JSONB;
  v_unit_price NUMERIC(12,2);
  v_line_total NUMERIC(12,2);
  v_total NUMERIC(12,2) := 0;
  v_qty INTEGER;
  v_unit public.unit_type;
  v_product_id UUID;
  v_existing_item_id UUID;
  v_existing_qty INTEGER;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'salesman' OR public.current_status() IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'only an active salesman can submit a daily summary';
  END IF;
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'summary must contain at least one line item';
  END IF;

  SELECT id INTO v_summary_id
    FROM public.daily_summaries
    WHERE salesman_id = auth.uid() AND submission_date = current_date AND status = 'booked'
    FOR UPDATE;

  IF v_summary_id IS NULL THEN
    INSERT INTO public.daily_summaries (salesman_id, submission_date, delivery_date, total_amount, status)
    VALUES (auth.uid(), current_date, current_date + 1, 0, 'booked')
    RETURNING id INTO v_summary_id;
  END IF;

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

    SELECT id, quantity INTO v_existing_item_id, v_existing_qty
      FROM public.daily_summary_items
      WHERE summary_id = v_summary_id AND product_id = v_product_id AND unit_type = v_unit
      FOR UPDATE;

    IF v_existing_item_id IS NOT NULL THEN
      v_qty := v_existing_qty + v_qty;
      v_line_total := v_unit_price * v_qty;
      UPDATE public.daily_summary_items
        SET quantity = v_qty, unit_price = v_unit_price, line_total = v_line_total
        WHERE id = v_existing_item_id;
    ELSE
      v_line_total := v_unit_price * v_qty;
      INSERT INTO public.daily_summary_items (summary_id, product_id, unit_type, quantity, unit_price, line_total)
      VALUES (v_summary_id, v_product_id, v_unit, v_qty, v_unit_price, v_line_total);
    END IF;
  END LOOP;

  SELECT COALESCE(SUM(line_total), 0) INTO v_total FROM public.daily_summary_items WHERE summary_id = v_summary_id;
  UPDATE public.daily_summaries SET total_amount = v_total, updated_at = now() WHERE id = v_summary_id;

  RETURN v_summary_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_daily_summary(JSONB) TO authenticated;
