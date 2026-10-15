-- ============================================================================
-- Orders that arrive after the van is loaded.
--
-- A salesman keeps taking orders through the day, and the delivery man is at
-- a shop that wants more than was booked. Both end up adding to an order
-- whose van has already left the warehouse.
--
-- That already half-worked: a second submission for the same salesman, day
-- and route merges into the open order. But nothing said the new lines were
-- not on the van, so the delivery man would arrive without goods he was
-- expected to have. This makes the gap visible and tells him about it.
-- ============================================================================

-- One row per order with a round in progress, saying what is ordered but not
-- yet on the van. The round screen shows this so the shortfall is obvious,
-- and "Load more" is how he closes it.
CREATE OR REPLACE VIEW public.pending_van_load
WITH (security_invoker = true) AS
SELECT
  d.id                                   AS delivery_id,
  d.summary_id,
  d.deliveryman_id,
  dsi.id                                 AS summary_item_id,
  dsi.product_id,
  p.name                                 AS product_name,
  dsi.unit_type,
  dsi.quantity                           AS ordered_quantity,
  COALESCE(di.loaded_quantity, 0)        AS loaded_quantity,
  dsi.quantity - COALESCE(di.loaded_quantity, 0) AS missing_quantity
FROM public.deliveries d
JOIN public.daily_summary_items dsi ON dsi.summary_id = d.summary_id
JOIN public.products p ON p.id = dsi.product_id
LEFT JOIN public.delivery_items di
       ON di.delivery_id = d.id AND di.summary_item_id = dsi.id
WHERE d.loaded_at IS NOT NULL
  AND d.returns_recorded_at IS NULL
  AND d.approval_status = 'pending'
  AND dsi.quantity > COALESCE(di.loaded_quantity, 0);

GRANT SELECT ON public.pending_van_load TO authenticated;

-- ============================================================================
-- The delivery man is told separately when something is added to an order he
-- has already loaded — that is not the same as a change he can take in his
-- stride, it means a trip back to the warehouse.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.notify_summary_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $fn$
DECLARE
  v_actor TEXT;
  v_actor_role public.user_role;
  v_route TEXT;
  v_owner RECORD;
  v_deliveryman UUID;
  v_loaded_round UUID;
  v_title TEXT;
  v_body TEXT;
  v_money TEXT;
  v_dm_title TEXT;
  v_dm_body TEXT;
BEGIN
  SELECT name, role INTO v_actor, v_actor_role FROM public.profiles WHERE user_id = auth.uid();
  v_actor := COALESCE(v_actor, 'Someone');

  SELECT COALESCE(r.name, 'a route') INTO v_route FROM public.routes r WHERE r.id = NEW.route_id;
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
    RETURN NEW;
  END IF;

  FOR v_owner IN
    SELECT user_id FROM public.profiles WHERE role = 'owner' AND status = 'active'
  LOOP
    CONTINUE WHEN v_owner.user_id = auth.uid();
    INSERT INTO public.notifications (user_id, kind, title, body, link)
    VALUES (v_owner.user_id, 'order_changed', v_title, v_body,
            '/owner/summaries/' || NEW.id);
  END LOOP;

  -- Is a van already out on this order?
  SELECT d.id, d.deliveryman_id INTO v_loaded_round, v_deliveryman
    FROM public.deliveries d
   WHERE d.summary_id = NEW.id
     AND d.loaded_at IS NOT NULL
     AND d.returns_recorded_at IS NULL
     AND d.approval_status = 'pending'
   LIMIT 1;

  IF v_loaded_round IS NULL THEN
    SELECT paired_deliveryman_id INTO v_deliveryman
      FROM public.profiles WHERE user_id = NEW.salesman_id;
    v_dm_title := v_title;
    v_dm_body := v_body;
  ELSE
    -- Loaded already: this is a trip back to the warehouse, not a detail.
    v_dm_title := 'Extra products added — not on your van';
    v_dm_body := v_actor || ' added to the ' || to_char(NEW.delivery_date, 'DD Mon')
                 || ' order on ' || v_route
                 || '. Open the round and use Load more to collect them.';
  END IF;

  IF v_deliveryman IS NOT NULL
     AND v_deliveryman <> COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid) THEN
    INSERT INTO public.notifications (user_id, kind, title, body, link)
    VALUES (v_deliveryman, 'order_changed', v_dm_title, v_dm_body, '/delivery/deliveries');
  END IF;

  RETURN NEW;
END;
$fn$;
