-- ============================================================================
-- close_delivery_round trusted the caller to send every line. Any line left
-- out kept delivered_quantity = 0 while its returned and damaged stayed 0 too
-- — so goods that went out in the van were recorded as neither sold, nor
-- returned, nor broken. They simply disappeared from the account, and because
-- stock is only deducted for delivered and damaged, the shelf count would
-- silently claim they were never taken.
--
-- Anything not reported on is now treated as having come back unsold, which
-- is the only reading that keeps loaded = delivered + returned + damaged true
-- for every line.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.close_delivery_round(p_delivery_id UUID, p_items JSONB)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_delivery RECORD;
  v_summary RECORD;
  v_item JSONB;
  v_line RECORD;
  v_returned INTEGER;
  v_damaged INTEGER;
  v_delivered INTEGER;
  v_delivered_value NUMERIC(12,2) := 0;
  v_damaged_value NUMERIC(12,2) := 0;
  v_payment NUMERIC(12,2);
  v_fully_delivered BOOLEAN := true;
  v_status public.order_status;
  v_reported UUID[] := ARRAY[]::UUID[];
BEGIN
  SELECT * INTO v_delivery FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF v_delivery IS NULL THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;
  IF v_delivery.deliveryman_id <> auth.uid() THEN
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
    v_damaged := COALESCE((v_item->>'damaged_quantity')::INTEGER, 0);
    IF v_returned < 0 OR v_damaged < 0 THEN
      RAISE EXCEPTION 'returned and damaged quantities must not be negative';
    END IF;
    IF v_returned + v_damaged > v_line.loaded_quantity THEN
      RAISE EXCEPTION 'returned plus damaged is more than what was loaded into the van';
    END IF;

    v_delivered := v_line.loaded_quantity - v_returned - v_damaged;
    IF v_delivered < v_line.ordered_quantity THEN
      v_fully_delivered := false;
    END IF;

    UPDATE public.delivery_items
       SET returned_quantity = v_returned,
           damaged_quantity = v_damaged,
           delivered_quantity = v_delivered
     WHERE id = v_line.id;

    v_reported := v_reported || v_line.id;
    v_delivered_value := v_delivered_value + v_delivered * v_line.unit_price;
    v_damaged_value := v_damaged_value + v_damaged * v_line.unit_price;
  END LOOP;

  -- Everything that went out but wasn't reported on came back unsold.
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
$$;
GRANT EXECUTE ON FUNCTION public.close_delivery_round(UUID, JSONB) TO authenticated;
