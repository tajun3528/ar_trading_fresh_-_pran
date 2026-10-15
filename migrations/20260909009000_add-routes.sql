-- ============================================================================
-- routes — a simple Owner-maintained list of the areas salesmen travel (e.g.
-- "Monipur Bazar"). No shops/territories attached (this app doesn't track
-- shops digitally) — it's just a label a salesman picks when starting a
-- daily summary, so orders for different areas on the same day stay
-- separate instead of merging into one.
-- ============================================================================
CREATE TABLE public.routes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER routes_updated_at BEFORE UPDATE ON public.routes
FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();

ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.routes TO authenticated;

CREATE POLICY routes_select ON public.routes FOR SELECT TO authenticated USING (true);

CREATE POLICY routes_write ON public.routes
  FOR ALL TO authenticated
  USING (public.current_role() = 'owner')
  WITH CHECK (public.current_role() = 'owner');

CREATE TRIGGER audit_routes AFTER INSERT OR UPDATE OR DELETE ON public.routes
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();

INSERT INTO public.routes (name) VALUES
  ('Monipur Bazar'),
  ('Hotapara'),
  ('Pirujali'),
  ('Ziya Road'),
  ('Vobanipur Bazar'),
  ('Bangla Bazar');

-- ============================================================================
-- daily_summaries.route_id — nullable (existing rows and the Quick Order
-- flow have none); a new memo-style submission always sets one.
-- ============================================================================
ALTER TABLE public.daily_summaries ADD COLUMN route_id UUID REFERENCES public.routes(id);

-- ============================================================================
-- submit_daily_summary — gains an optional route + a salesman-chosen
-- delivery date (must still be after today). Same-day submissions now merge
-- per (salesman, date, route) instead of just (salesman, date), so a
-- salesman covering two routes in one day gets two separate summaries.
-- Old 1-arg signature is dropped first: leaving both would make a
-- 1-argument RPC call ambiguous between the two overloads.
-- ============================================================================
DROP FUNCTION IF EXISTS public.submit_daily_summary(JSONB);

CREATE OR REPLACE FUNCTION public.submit_daily_summary(
  p_items JSONB,
  p_route_id UUID DEFAULT NULL,
  p_delivery_date DATE DEFAULT NULL
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

  v_delivery_date := COALESCE(p_delivery_date, current_date + 1);
  IF v_delivery_date <= current_date THEN
    RAISE EXCEPTION 'delivery date must be after today';
  END IF;

  IF p_route_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.routes WHERE id = p_route_id AND is_active
  ) THEN
    RAISE EXCEPTION 'route not found or inactive';
  END IF;

  SELECT id INTO v_summary_id
    FROM public.daily_summaries
    WHERE salesman_id = auth.uid() AND submission_date = current_date AND status = 'booked'
      AND route_id IS NOT DISTINCT FROM p_route_id
    FOR UPDATE;

  IF v_summary_id IS NULL THEN
    INSERT INTO public.daily_summaries (salesman_id, submission_date, delivery_date, total_amount, status, company_id, route_id)
    VALUES (auth.uid(), current_date, v_delivery_date, 0, 'booked', v_company_id, p_route_id)
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

  SELECT COALESCE(SUM(line_total), 0) INTO v_total FROM public.daily_summary_items WHERE summary_id = v_summary_id;
  UPDATE public.daily_summaries SET total_amount = v_total, updated_at = now() WHERE id = v_summary_id;

  RETURN v_summary_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.submit_daily_summary(JSONB, UUID, DATE) TO authenticated;
