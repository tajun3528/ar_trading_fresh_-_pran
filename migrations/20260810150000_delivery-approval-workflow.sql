-- ============================================================================
-- Delivery confirmation now requires Owner approval before it counts as a
-- completed sale — mirroring the return/damage approval workflow. Previously
-- confirm_summary_delivery() decremented stock and flipped daily_summaries
-- to 'delivered'/'partially_delivered' immediately on the deliveryman's own
-- say-so (which is exactly what "Total Sales" and every revenue report
-- filter on). Now:
--   1. confirm_summary_delivery() only files a pending claim (delivery_items
--      recorded, no stock/summary-status change).
--   2. approve_delivery() (Owner-only) is what actually decrements stock and
--      flips daily_summaries.status — this is the moment a sale counts.
--   3. reject_delivery() (Owner-only) discards the claim with no effect;
--      daily_summaries.status was never advanced, so the deliveryman can
--      simply re-report.
-- ============================================================================

CREATE TYPE public.approval_status AS ENUM ('pending', 'approved', 'rejected');

ALTER TABLE public.deliveries
  ADD COLUMN approval_status public.approval_status NOT NULL DEFAULT 'pending',
  ADD COLUMN approved_by UUID REFERENCES public.profiles(user_id),
  ADD COLUMN approved_at TIMESTAMPTZ,
  ADD COLUMN rejection_reason TEXT;

-- Existing deliveries already happened under the old immediate-effect model
-- (stock already decremented, sales already counted) — don't retroactively
-- mark real history as pending.
UPDATE public.deliveries SET approval_status = 'approved', approved_at = created_at
WHERE status IN ('delivered', 'partially_delivered');

-- ============================================================================
-- confirm_summary_delivery — files the deliveryman's claim only.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.confirm_summary_delivery(p_summary_id UUID, p_items JSONB)
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
  v_delivered_qty INTEGER;
  v_fully_delivered BOOLEAN := true;
  v_seen_items INTEGER := 0;
  v_status public.order_status;
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
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'delivery must contain at least one line item';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.deliveries WHERE summary_id = p_summary_id AND approval_status = 'pending'
  ) THEN
    RAISE EXCEPTION 'a delivery report for this summary is already waiting on owner approval';
  END IF;

  INSERT INTO public.deliveries (summary_id, deliveryman_id, delivery_datetime, status, approval_status)
  VALUES (p_summary_id, auth.uid(), now(), 'delivered', 'pending')
  RETURNING id INTO v_delivery_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_summary_item FROM public.daily_summary_items
      WHERE id = (v_item->>'summary_item_id')::UUID AND summary_id = p_summary_id;
    IF v_summary_item IS NULL THEN
      RAISE EXCEPTION 'summary item not found on this summary';
    END IF;
    v_seen_items := v_seen_items + 1;

    v_delivered_qty := (v_item->>'delivered_quantity')::INTEGER;
    IF v_delivered_qty IS NULL OR v_delivered_qty < 0 THEN
      RAISE EXCEPTION 'delivered quantity must not be negative';
    END IF;
    IF v_delivered_qty > v_summary_item.quantity THEN
      RAISE EXCEPTION 'delivered quantity exceeds requested quantity';
    END IF;
    IF v_delivered_qty < v_summary_item.quantity THEN
      v_fully_delivered := false;
    END IF;

    INSERT INTO public.delivery_items (delivery_id, summary_item_id, delivered_quantity)
    VALUES (v_delivery_id, v_summary_item.id, v_delivered_qty);
  END LOOP;

  IF v_seen_items <> (SELECT count(*) FROM public.daily_summary_items WHERE summary_id = p_summary_id) THEN
    v_fully_delivered := false;
  END IF;

  v_status := CASE WHEN v_fully_delivered THEN 'delivered' ELSE 'partially_delivered' END::public.order_status;
  UPDATE public.deliveries SET status = v_status WHERE id = v_delivery_id;

  RETURN v_delivery_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.confirm_summary_delivery(UUID, JSONB) TO authenticated;

-- ============================================================================
-- approve_delivery — Owner-only. This is the moment stock actually moves and
-- the summary (and the sale it represents) becomes final.
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

  FOR v_item IN
    SELECT di.delivered_quantity, dsi.product_id, dsi.unit_type
    FROM public.delivery_items di
    JOIN public.daily_summary_items dsi ON dsi.id = di.summary_item_id
    WHERE di.delivery_id = p_delivery_id
  LOOP
    IF v_item.delivered_quantity = 0 THEN
      CONTINUE;
    END IF;

    SELECT available_qty INTO v_available FROM public.stock
      WHERE product_id = v_item.product_id AND unit_type = v_item.unit_type FOR UPDATE;
    IF v_available IS NULL OR v_available < v_item.delivered_quantity THEN
      RAISE EXCEPTION 'insufficient % stock for product %', v_item.unit_type, v_item.product_id;
    END IF;

    UPDATE public.stock SET available_qty = available_qty - v_item.delivered_quantity, updated_at = now()
      WHERE product_id = v_item.product_id AND unit_type = v_item.unit_type;
  END LOOP;

  UPDATE public.daily_summaries SET status = v_delivery.status, updated_at = now() WHERE id = v_delivery.summary_id;
  UPDATE public.deliveries
    SET approval_status = 'approved', approved_by = auth.uid(), approved_at = now()
    WHERE id = p_delivery_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.approve_delivery(UUID) TO authenticated;

-- ============================================================================
-- reject_delivery — Owner-only. No stock/summary effect; the summary was
-- never advanced off 'booked'/'partially_delivered', so the deliveryman can
-- simply file a corrected report.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.reject_delivery(p_delivery_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_status public.approval_status;
BEGIN
  IF public.current_role() != 'owner' THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT approval_status INTO v_status FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;
  IF v_status != 'pending' THEN
    RAISE EXCEPTION 'delivery is already %', v_status;
  END IF;

  UPDATE public.deliveries
    SET approval_status = 'rejected', approved_by = auth.uid(), approved_at = now(), rejection_reason = p_reason
    WHERE id = p_delivery_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.reject_delivery(UUID, TEXT) TO authenticated;
