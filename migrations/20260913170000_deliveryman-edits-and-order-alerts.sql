-- ============================================================================
-- Two things the owner asked for.
--
-- 1. The delivery man can change an order. In the field a shop often wants
--    more than was booked, and until now the round could only ever record
--    LESS than the order: delivered, returned, damaged. There was no way to
--    sell a product the shop actually wanted, so it happened on paper and
--    never reached the app.
--
-- 2. The owner is told whenever an order is created, changed or cancelled —
--    by either the salesman or the delivery man. Orders were the one part of
--    the business that moved without the owner hearing about it.
-- ============================================================================

-- Marks the lines the delivery man added himself, so the approval screen can
-- show what changed after the order was booked rather than silently showing a
-- different total than the salesman submitted.
ALTER TABLE public.delivery_items
  ADD COLUMN added_by_deliveryman BOOLEAN NOT NULL DEFAULT false;

-- A round carries one row per order line, which was always true in practice
-- but never enforced. add_delivery_line relies on it to top up an existing
-- line instead of creating a second row for the same product.
ALTER TABLE public.delivery_items
  ADD CONSTRAINT delivery_items_unique_line UNIQUE (delivery_id, summary_item_id);

-- One switch covering every order alert, so Profile does not grow a toggle
-- per event.
ALTER TABLE public.user_preferences
  ADD COLUMN notify_order_changes BOOLEAN NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.save_my_preferences(p_patch JSONB)
RETURNS public.user_preferences
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_row public.user_preferences;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;

  INSERT INTO public.user_preferences (user_id) VALUES (auth.uid())
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE public.user_preferences p SET
    theme_mode               = COALESCE(p_patch->>'theme_mode', p.theme_mode),
    text_scale               = COALESCE((p_patch->>'text_scale')::NUMERIC, p.text_scale),
    density                  = COALESCE(p_patch->>'density', p.density),
    accent                   = COALESCE(p_patch->>'accent', p.accent),
    reduce_motion            = COALESCE((p_patch->>'reduce_motion')::BOOLEAN, p.reduce_motion),
    landing_route            = CASE WHEN p_patch ? 'landing_route'
                                    THEN NULLIF(p_patch->>'landing_route', '')
                                    ELSE p.landing_route END,
    notify_awaiting_approval = COALESCE((p_patch->>'notify_awaiting_approval')::BOOLEAN, p.notify_awaiting_approval),
    notify_rejected          = COALESCE((p_patch->>'notify_rejected')::BOOLEAN, p.notify_rejected),
    notify_approved          = COALESCE((p_patch->>'notify_approved')::BOOLEAN, p.notify_approved),
    notify_order_changes     = COALESCE((p_patch->>'notify_order_changes')::BOOLEAN, p.notify_order_changes),
    updated_at               = now()
  WHERE p.user_id = auth.uid()
  RETURNING p.* INTO v_row;

  RETURN v_row;
END;
$$;
GRANT EXECUTE ON FUNCTION public.save_my_preferences(JSONB) TO authenticated;

-- ============================================================================
-- edit_daily_summary — the paired delivery man may now edit too, before the
-- van is loaded. Same window and same rules as the salesman otherwise.
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
  -- The salesman who booked it, or the delivery man who will carry it.
  IF v_summary.salesman_id IS DISTINCT FROM auth.uid()
     AND NOT public.is_paired_deliveryman(v_summary.salesman_id) THEN
    RAISE EXCEPTION 'not your summary';
  END IF;
  IF v_summary.status <> 'booked' THEN
    RAISE EXCEPTION 'summary can no longer be edited';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.deliveries
     WHERE summary_id = p_summary_id AND approval_status <> 'rejected'
  ) THEN
    RAISE EXCEPTION 'the van has already been loaded for this order — add the product from the delivery round instead';
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

  UPDATE public.daily_summaries
     SET total_amount = v_total,
         commission_amount = COALESCE(p_commission_amount, commission_amount),
         updated_at = now()
   WHERE id = p_summary_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.edit_daily_summary(UUID, JSONB, NUMERIC) TO authenticated;

-- ============================================================================
-- add_delivery_line — the delivery man sells something extra at the shop.
--
-- Adds the line to the order itself (so it is priced, counted and earns
-- profit exactly like any other line) and puts a matching row on the round
-- marked as loaded, because the goods are going out of the van now.
--
-- Stock is not deducted here: approval is what moves stock for every other
-- line, and doing it here would double-count. That also means the owner's
-- approval remains the one place a shortfall is caught.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.add_delivery_line(
  p_delivery_id UUID,
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_quantity INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_delivery RECORD;
  v_summary RECORD;
  v_product RECORD;
  v_item_id UUID;
  v_total NUMERIC(12,2);
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be more than zero';
  END IF;

  SELECT * INTO v_delivery FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF v_delivery IS NULL THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;
  IF v_delivery.deliveryman_id <> auth.uid() THEN
    RAISE EXCEPTION 'not your delivery';
  END IF;
  IF v_delivery.loaded_at IS NULL THEN
    RAISE EXCEPTION 'load the van before adding products to the round';
  END IF;
  IF v_delivery.returns_recorded_at IS NOT NULL THEN
    RAISE EXCEPTION 'this round is already closed and waiting on owner approval';
  END IF;

  SELECT * INTO v_summary FROM public.daily_summaries WHERE id = v_delivery.summary_id FOR UPDATE;

  -- Only this company's catalog: a round must never mix two vendors' goods.
  SELECT id, name, company_id INTO v_product FROM public.products WHERE id = p_product_id;
  IF v_product IS NULL THEN
    RAISE EXCEPTION 'product not found';
  END IF;
  IF v_product.company_id IS DISTINCT FROM v_summary.company_id THEN
    RAISE EXCEPTION 'that product belongs to a different company';
  END IF;

  -- Prices and rolls up cartons exactly as a salesman's own line would.
  PERFORM public._apply_summary_item(
    v_delivery.summary_id, p_product_id, p_unit_type, p_quantity, v_summary.company_id);

  SELECT id INTO v_item_id
    FROM public.daily_summary_items
   WHERE summary_id = v_delivery.summary_id
     AND product_id = p_product_id
     AND unit_type = p_unit_type;

  -- The goods leave the van now, so the line counts as loaded. If the product
  -- was already on the round, top up what went out rather than duplicating it.
  INSERT INTO public.delivery_items (
    delivery_id, summary_item_id, loaded_quantity, delivered_quantity,
    returned_quantity, damaged_quantity, added_by_deliveryman)
  VALUES (p_delivery_id, v_item_id, p_quantity, 0, 0, 0, true)
  ON CONFLICT (delivery_id, summary_item_id) DO UPDATE
    SET loaded_quantity = public.delivery_items.loaded_quantity + EXCLUDED.loaded_quantity,
        added_by_deliveryman = true;

  SELECT COALESCE(SUM(line_total), 0) INTO v_total
    FROM public.daily_summary_items WHERE summary_id = v_delivery.summary_id;
  UPDATE public.daily_summaries
     SET total_amount = v_total, updated_at = now()
   WHERE id = v_delivery.summary_id;

  RETURN v_item_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.add_delivery_line(UUID, UUID, public.unit_type, INTEGER) TO authenticated;

-- ============================================================================
-- notify_summary_change — the owner hears about every order.
--
-- A trigger rather than a call inside each RPC, so any future path that books
-- or changes an order still reports it. It names the actor by looking at who
-- is signed in, which is also how a delivery man's change is told apart from
-- the salesman's own.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.notify_summary_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_actor TEXT;
  v_actor_role public.user_role;
  v_route TEXT;
  v_owner RECORD;
  v_title TEXT;
  v_body TEXT;
  v_money TEXT;
BEGIN
  SELECT name, role INTO v_actor, v_actor_role FROM public.profiles WHERE user_id = auth.uid();
  v_actor := COALESCE(v_actor, 'Someone');

  SELECT COALESCE(r.name, 'a route') INTO v_route
    FROM public.routes r WHERE r.id = NEW.route_id;
  v_route := COALESCE(v_route, 'a route');
  v_money := to_char(COALESCE(NEW.total_amount, 0), 'FM999,999,990.00');

  IF TG_OP = 'INSERT' THEN
    v_title := 'New order booked';
    v_body := v_actor || ' booked ' || v_route || ' for '
              || to_char(NEW.delivery_date, 'DD Mon') || ' — ৳' || v_money || '.';

  ELSIF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
    v_title := 'Order cancelled';
    v_body := v_actor || ' cancelled the ' || to_char(NEW.delivery_date, 'DD Mon')
              || ' order on ' || v_route || '.';

  ELSIF NEW.total_amount IS DISTINCT FROM OLD.total_amount
     OR NEW.commission_amount IS DISTINCT FROM OLD.commission_amount THEN
    -- A delivery man changing the total is him selling extra at a shop, which
    -- is a different event to a salesman revising a booking.
    IF v_actor_role = 'deliveryman' THEN
      v_title := 'Delivery man added to an order';
      v_body := v_actor || ' added products on ' || v_route || ' — the '
                || to_char(NEW.delivery_date, 'DD Mon') || ' order is now ৳' || v_money || '.';
    ELSE
      v_title := 'Order changed';
      v_body := v_actor || ' changed the ' || to_char(NEW.delivery_date, 'DD Mon')
                || ' order on ' || v_route || ' — now ৳' || v_money || '.';
    END IF;

  ELSE
    -- Status moving through the delivery flow is already reported by the
    -- delivery notifications; nothing to say here.
    RETURN NEW;
  END IF;

  FOR v_owner IN
    SELECT user_id FROM public.profiles WHERE role = 'owner' AND status = 'active'
  LOOP
    -- The owner booking or editing on their own behalf does not need telling.
    CONTINUE WHEN v_owner.user_id = auth.uid();
    INSERT INTO public.notifications (user_id, kind, title, body, link)
    VALUES (v_owner.user_id, 'order_changed', v_title, v_body,
            '/owner/summaries/' || NEW.id);
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE TRIGGER notify_summary_change
AFTER INSERT OR UPDATE ON public.daily_summaries
FOR EACH ROW EXECUTE FUNCTION public.notify_summary_change();
