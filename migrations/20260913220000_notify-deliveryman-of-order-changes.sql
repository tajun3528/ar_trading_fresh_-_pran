-- ============================================================================
-- The delivery man needs to know too.
--
-- A salesman can change an order right up until the van is loaded, and until
-- now only the owner heard about it. The person it affects most is the
-- delivery man: he is the one who will load that van, and he was finding out
-- by discovering different quantities in the morning.
--
-- Same trigger, now writing to the salesman's paired delivery man as well,
-- each with a link into their own part of the app.
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
  v_title TEXT;
  v_body TEXT;
  v_money TEXT;
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

  -- ------------------------------------------------------------- the owners
  FOR v_owner IN
    SELECT user_id FROM public.profiles WHERE role = 'owner' AND status = 'active'
  LOOP
    CONTINUE WHEN v_owner.user_id = auth.uid();
    INSERT INTO public.notifications (user_id, kind, title, body, link)
    VALUES (v_owner.user_id, 'order_changed', v_title, v_body,
            '/owner/summaries/' || NEW.id);
  END LOOP;

  -- ------------------------------------------------- the salesman's own man
  -- He is the one who has to load this van, so a change to what is on the
  -- order reaches him directly rather than being discovered in the morning.
  SELECT paired_deliveryman_id INTO v_deliveryman
    FROM public.profiles WHERE user_id = NEW.salesman_id;

  IF v_deliveryman IS NOT NULL AND v_deliveryman <> COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid) THEN
    INSERT INTO public.notifications (user_id, kind, title, body, link)
    VALUES (v_deliveryman, 'order_changed', v_title, v_body, '/delivery/deliveries');
  END IF;

  RETURN NEW;
END;
$fn$;
