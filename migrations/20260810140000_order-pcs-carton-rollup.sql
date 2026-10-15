-- ============================================================================
-- Orders now get the same pcs->carton rollup stock_in() already applies:
-- if a product's pcs_per_carton is set and a salesman requests enough loose
-- pieces to fill one or more full cartons, the order line records cartons
-- (plus any leftover pieces as their own line) instead of a pile of pieces.
-- Only applies where a carton price actually exists for the product — a
-- product never sold by the carton just keeps its pcs line as before.
--
-- Shared by submit_daily_summary and edit_daily_summary via two small
-- helpers so the rollup logic lives in exactly one place.
-- ============================================================================

CREATE OR REPLACE FUNCTION public._upsert_summary_item(
  p_summary_id UUID,
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_quantity INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_unit_price NUMERIC(12,2);
  v_existing_item_id UUID;
  v_existing_qty INTEGER;
  v_new_qty INTEGER;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RETURN;
  END IF;

  SELECT pu.price INTO v_unit_price
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
    WHERE pu.product_id = p_product_id AND pu.unit_type = p_unit_type AND p.is_active;
  IF v_unit_price IS NULL THEN
    RAISE EXCEPTION 'no active price for the given product/unit';
  END IF;

  SELECT id, quantity INTO v_existing_item_id, v_existing_qty
    FROM public.daily_summary_items
    WHERE summary_id = p_summary_id AND product_id = p_product_id AND unit_type = p_unit_type
    FOR UPDATE;

  IF v_existing_item_id IS NOT NULL THEN
    v_new_qty := v_existing_qty + p_quantity;
    UPDATE public.daily_summary_items
      SET quantity = v_new_qty, unit_price = v_unit_price, line_total = v_unit_price * v_new_qty
      WHERE id = v_existing_item_id;
  ELSE
    INSERT INTO public.daily_summary_items (summary_id, product_id, unit_type, quantity, unit_price, line_total)
    VALUES (p_summary_id, p_product_id, p_unit_type, p_quantity, v_unit_price, v_unit_price * p_quantity);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._apply_summary_item(
  p_summary_id UUID,
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_quantity INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_pcs_per_carton INTEGER;
  v_full_cartons INTEGER;
  v_remainder INTEGER;
  v_carton_price NUMERIC(12,2);
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be positive';
  END IF;

  IF p_unit_type = 'pcs' THEN
    SELECT pcs_per_carton INTO v_pcs_per_carton FROM public.products WHERE id = p_product_id;
    IF v_pcs_per_carton IS NOT NULL AND p_quantity >= v_pcs_per_carton THEN
      SELECT pu.price INTO v_carton_price
        FROM public.product_units pu
        JOIN public.products p ON p.id = pu.product_id
        WHERE pu.product_id = p_product_id AND pu.unit_type = 'carton' AND p.is_active;

      IF v_carton_price IS NOT NULL THEN
        v_full_cartons := p_quantity / v_pcs_per_carton;
        v_remainder := p_quantity % v_pcs_per_carton;

        PERFORM public._upsert_summary_item(p_summary_id, p_product_id, 'carton', v_full_cartons);
        IF v_remainder > 0 THEN
          PERFORM public._upsert_summary_item(p_summary_id, p_product_id, 'pcs', v_remainder);
        END IF;
        RETURN;
      END IF;
    END IF;
  END IF;

  PERFORM public._upsert_summary_item(p_summary_id, p_product_id, p_unit_type, p_quantity);
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_daily_summary(p_items JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_summary_id UUID;
  v_item JSONB;
  v_total NUMERIC(12,2);
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
    PERFORM public._apply_summary_item(
      v_summary_id,
      (v_item->>'product_id')::UUID,
      (v_item->>'unit_type')::public.unit_type,
      (v_item->>'quantity')::INTEGER
    );
  END LOOP;

  SELECT COALESCE(SUM(line_total), 0) INTO v_total FROM public.daily_summary_items WHERE summary_id = v_summary_id;
  UPDATE public.daily_summaries SET total_amount = v_total, updated_at = now() WHERE id = v_summary_id;

  RETURN v_summary_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.submit_daily_summary(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.edit_daily_summary(p_summary_id UUID, p_items JSONB)
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

  DELETE FROM public.daily_summary_items WHERE summary_id = p_summary_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    PERFORM public._apply_summary_item(
      p_summary_id,
      (v_item->>'product_id')::UUID,
      (v_item->>'unit_type')::public.unit_type,
      (v_item->>'quantity')::INTEGER
    );
  END LOOP;

  SELECT COALESCE(SUM(line_total), 0) INTO v_total FROM public.daily_summary_items WHERE summary_id = p_summary_id;
  UPDATE public.daily_summaries SET total_amount = v_total, updated_at = now() WHERE id = p_summary_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.edit_daily_summary(UUID, JSONB) TO authenticated;
