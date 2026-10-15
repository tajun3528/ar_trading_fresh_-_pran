-- ============================================================================
-- Delivery becomes the two-stage round the deliveryman actually works:
--
--   1. Load the van — tick each line that is physically aboard. Lines not
--      ticked never leave, so they can't be delivered.
--   2. Come back — enter what returned unsold and what came back broken.
--      Delivered is what's left: loaded − returned − damaged.
--
-- Then the cash to hand over is worked out and the report goes to the Owner.
--
-- Stock still only moves on the Owner's approval, so goods sitting in the van
-- mid-round are neither lost nor double-counted. On approval:
--   delivered  → comes off available stock (a sale)
--   damaged    → moves from available into the damaged count
--   returned   → untouched; it never left the shelf in the books
-- ============================================================================
ALTER TABLE public.delivery_items ADD COLUMN loaded_quantity INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.delivery_items ADD COLUMN returned_quantity INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.delivery_items ADD COLUMN damaged_quantity INTEGER NOT NULL DEFAULT 0;

ALTER TABLE public.deliveries ADD COLUMN loaded_at TIMESTAMPTZ;
ALTER TABLE public.deliveries ADD COLUMN returns_recorded_at TIMESTAMPTZ;
ALTER TABLE public.deliveries ADD COLUMN payment_amount NUMERIC(12,2);

-- Existing reports predate the van stages: treat what they delivered as
-- having been loaded, so the arithmetic below holds for them too.
UPDATE public.delivery_items SET loaded_quantity = delivered_quantity WHERE loaded_quantity = 0;

-- ============================================================================
-- load_delivery_van — stage 1. Opens the round with what's aboard.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.load_delivery_van(p_summary_id UUID, p_items JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
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
  IF NOT public.is_paired_deliveryman(v_summary.salesman_id) THEN
    RAISE EXCEPTION 'not your paired salesman';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.deliveries WHERE summary_id = p_summary_id AND approval_status = 'pending'
  ) THEN
    RAISE EXCEPTION 'this order already has a delivery in progress or waiting on owner approval';
  END IF;

  INSERT INTO public.deliveries (summary_id, deliveryman_id, delivery_datetime, status, approval_status, loaded_at)
  VALUES (p_summary_id, auth.uid(), now(), 'booked', 'pending', now())
  RETURNING id INTO v_delivery_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_summary_item FROM public.daily_summary_items
      WHERE id = (v_item->>'summary_item_id')::UUID AND summary_id = p_summary_id;
    IF v_summary_item IS NULL THEN
      RAISE EXCEPTION 'summary item not found on this summary';
    END IF;

    v_loaded := COALESCE((v_item->>'loaded_quantity')::INTEGER, 0);
    IF v_loaded < 0 OR v_loaded > v_summary_item.quantity THEN
      RAISE EXCEPTION 'loaded quantity must be between 0 and the ordered quantity';
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
$$;
GRANT EXECUTE ON FUNCTION public.load_delivery_van(UUID, JSONB) TO authenticated;

-- ============================================================================
-- close_delivery_round — stage 2. Records what came back and works out the
-- cash owed, then hands the report to the Owner.
--
-- Payment is delivered value less the salesman's commission less the value of
-- what came back broken, per the Owner's rule.
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

    v_delivered_value := v_delivered_value + v_delivered * v_line.unit_price;
    v_damaged_value := v_damaged_value + v_damaged * v_line.unit_price;
  END LOOP;

  -- Any line the deliveryman didn't touch stays at zero delivered, which
  -- also means the order wasn't fully delivered.
  IF EXISTS (
    SELECT 1 FROM public.delivery_items
     WHERE delivery_id = p_delivery_id AND delivered_quantity = 0 AND loaded_quantity > 0
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

-- ============================================================================
-- approve_delivery — now also moves broken goods into the damaged count, and
-- refuses to approve a round that is still out on the road.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.approve_delivery(p_delivery_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_delivery RECORD;
  v_item RECORD;
  v_available INTEGER;
  v_to_remove INTEGER;
BEGIN
  IF public.current_role() != 'owner' THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT * INTO v_delivery FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF v_delivery IS NULL THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;
  IF v_delivery.approval_status != 'pending' THEN
    RAISE EXCEPTION 'delivery is already %', v_delivery.approval_status;
  END IF;
  IF v_delivery.loaded_at IS NOT NULL AND v_delivery.returns_recorded_at IS NULL THEN
    RAISE EXCEPTION 'this round is still out — the deliveryman has not recorded returns yet';
  END IF;

  FOR v_item IN
    SELECT di.delivered_quantity, di.damaged_quantity, dsi.product_id, dsi.unit_type
    FROM public.delivery_items di
    JOIN public.daily_summary_items dsi ON dsi.id = di.summary_item_id
    WHERE di.delivery_id = p_delivery_id
  LOOP
    -- Sold goods leave; broken goods leave the sellable count too, but stay
    -- on the books as damage.
    v_to_remove := v_item.delivered_quantity + v_item.damaged_quantity;
    IF v_to_remove = 0 THEN
      CONTINUE;
    END IF;

    SELECT available_qty INTO v_available FROM public.stock
      WHERE product_id = v_item.product_id AND unit_type = v_item.unit_type FOR UPDATE;
    IF v_available IS NULL OR v_available < v_to_remove THEN
      RAISE EXCEPTION 'insufficient % stock for product %', v_item.unit_type, v_item.product_id;
    END IF;

    UPDATE public.stock
       SET available_qty = available_qty - v_to_remove,
           damaged_qty = damaged_qty + v_item.damaged_quantity,
           updated_at = now()
     WHERE product_id = v_item.product_id AND unit_type = v_item.unit_type;
  END LOOP;

  UPDATE public.daily_summaries SET status = v_delivery.status, updated_at = now() WHERE id = v_delivery.summary_id;
  UPDATE public.deliveries
    SET approval_status = 'approved', approved_by = auth.uid(), approved_at = now()
    WHERE id = p_delivery_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.approve_delivery(UUID) TO authenticated;
