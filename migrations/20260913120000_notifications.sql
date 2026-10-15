-- ============================================================================
-- Tell people things instead of making them go looking.
--
-- Today the owner learns a round is waiting for approval by opening the
-- dashboard, and a salesman learns his order was rejected only if he happens
-- to check. Both are time-sensitive: an unapproved round holds up stock and
-- profit, and a rejected report needs redoing the same day.
--
-- Notifications are raised by triggers on deliveries rather than from inside
-- close_delivery_round / approve_delivery / reject_delivery, so the money
-- logic in those functions is left exactly as it is — and any future path
-- that moves a delivery still notifies.
-- ============================================================================
CREATE TABLE public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  -- Where tapping it should go, as an in-app route.
  link TEXT,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX notifications_inbox ON public.notifications (user_id, read_at, created_at DESC);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
GRANT SELECT, UPDATE, DELETE ON public.notifications TO authenticated;

-- You only ever see your own, and the only thing you may change is whether
-- you have read it. Inserts come from the triggers (SECURITY DEFINER), never
-- from a client.
CREATE POLICY notifications_select ON public.notifications
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY notifications_update ON public.notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY notifications_delete ON public.notifications
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- ============================================================================
-- notify_delivery_change — one trigger covering the three moments that matter.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.notify_delivery_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_summary RECORD;
  v_deliveryman TEXT;
  v_route TEXT;
  v_owner RECORD;
BEGIN
  SELECT s.salesman_id, s.delivery_date, r.name AS route_name
    INTO v_summary
    FROM public.daily_summaries s
    LEFT JOIN public.routes r ON r.id = s.route_id
   WHERE s.id = NEW.summary_id;

  SELECT name INTO v_deliveryman FROM public.profiles WHERE user_id = NEW.deliveryman_id;
  v_route := COALESCE(v_summary.route_name, 'a route');

  -- ---------------------------------------------- round submitted for review
  -- payment_amount lands when the deliveryman closes the round, which is the
  -- moment it starts waiting on the owner.
  IF NEW.approval_status = 'pending'
     AND NEW.payment_amount IS NOT NULL
     AND OLD.payment_amount IS DISTINCT FROM NEW.payment_amount THEN
    FOR v_owner IN
      SELECT user_id FROM public.profiles WHERE role = 'owner' AND status = 'active'
    LOOP
      INSERT INTO public.notifications (user_id, kind, title, body, link)
      VALUES (
        v_owner.user_id,
        'delivery_awaiting_approval',
        'Round awaiting approval',
        COALESCE(v_deliveryman, 'A delivery man') || ' finished ' || v_route
          || ' — ৳' || to_char(NEW.payment_amount, 'FM999,999,990.00') || ' to hand over.',
        '/owner/deliveries'
      );
    END LOOP;
  END IF;

  -- ------------------------------------------------------------- rejected
  IF NEW.approval_status = 'rejected' AND OLD.approval_status IS DISTINCT FROM 'rejected' THEN
    INSERT INTO public.notifications (user_id, kind, title, body, link)
    VALUES (
      NEW.deliveryman_id,
      'delivery_rejected',
      'Delivery report rejected',
      'Your report for ' || v_route || ' needs redoing'
        || COALESCE(' — reason: ' || NEW.rejection_reason, '.'),
      '/delivery/deliveries'
    );

    IF v_summary.salesman_id IS NOT NULL THEN
      INSERT INTO public.notifications (user_id, kind, title, body, link)
      VALUES (
        v_summary.salesman_id,
        'delivery_rejected',
        'Delivery report rejected',
        'The report for your ' || to_char(v_summary.delivery_date, 'DD Mon') || ' order on '
          || v_route || ' was sent back to the delivery man.',
        '/salesman/summaries'
      );
    END IF;
  END IF;

  -- ------------------------------------------------------------- approved
  IF NEW.approval_status = 'approved' AND OLD.approval_status IS DISTINCT FROM 'approved' THEN
    INSERT INTO public.notifications (user_id, kind, title, body, link)
    VALUES (
      NEW.deliveryman_id,
      'delivery_approved',
      'Round approved',
      v_route || ' is settled — ৳' || to_char(COALESCE(NEW.payment_amount, 0), 'FM999,999,990.00')
        || ' accounted for.',
      '/delivery/history'
    );

    IF v_summary.salesman_id IS NOT NULL THEN
      INSERT INTO public.notifications (user_id, kind, title, body, link)
      VALUES (
        v_summary.salesman_id,
        'delivery_approved',
        'Order delivered and approved',
        'Your ' || to_char(v_summary.delivery_date, 'DD Mon') || ' order on ' || v_route
          || ' is settled. Its profit is now counted.',
        '/salesman/summaries'
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER notify_delivery_change
AFTER UPDATE ON public.deliveries
FOR EACH ROW EXECUTE FUNCTION public.notify_delivery_change();

-- ============================================================================
-- mark_notifications_read — one call for the bell, rather than a row at a time.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.mark_notifications_read(p_ids UUID[] DEFAULT NULL)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.notifications
     SET read_at = now()
   WHERE user_id = auth.uid()
     AND read_at IS NULL
     AND (p_ids IS NULL OR id = ANY(p_ids));
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read(UUID[]) TO authenticated;
