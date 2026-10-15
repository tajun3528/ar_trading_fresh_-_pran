-- Pairing replaces the old Route: each salesman is paired with one delivery
-- man directly on their profile, owner-assigned via the Users screen.
ALTER TABLE public.profiles ADD COLUMN paired_deliveryman_id UUID REFERENCES public.profiles(user_id);
CREATE INDEX idx_profiles_paired_deliveryman_id ON public.profiles(paired_deliveryman_id);

-- daily_summaries: one aggregate "tomorrow's demand" submission per salesman
-- per day, replacing per-shop orders. Shop-level dealing stays on paper.
CREATE TABLE public.daily_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  salesman_id UUID NOT NULL REFERENCES public.profiles(user_id),
  submission_date DATE NOT NULL DEFAULT current_date,
  delivery_date DATE NOT NULL,
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  status public.order_status NOT NULL DEFAULT 'booked',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_daily_summaries_salesman_id ON public.daily_summaries(salesman_id);
CREATE INDEX idx_daily_summaries_delivery_date ON public.daily_summaries(delivery_date);

CREATE TABLE public.daily_summary_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  summary_id UUID NOT NULL REFERENCES public.daily_summaries(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id),
  unit_type public.unit_type NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
  line_total NUMERIC(12,2) NOT NULL CHECK (line_total >= 0)
);
CREATE INDEX idx_daily_summary_items_summary_id ON public.daily_summary_items(summary_id);

CREATE TABLE public.deliveries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  summary_id UUID NOT NULL REFERENCES public.daily_summaries(id),
  deliveryman_id UUID NOT NULL REFERENCES public.profiles(user_id),
  delivery_datetime TIMESTAMPTZ NOT NULL DEFAULT now(),
  status public.order_status NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_deliveries_summary_id ON public.deliveries(summary_id);
CREATE INDEX idx_deliveries_deliveryman_id ON public.deliveries(deliveryman_id);

CREATE TABLE public.delivery_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id UUID NOT NULL REFERENCES public.deliveries(id) ON DELETE CASCADE,
  summary_item_id UUID NOT NULL REFERENCES public.daily_summary_items(id),
  delivered_quantity INTEGER NOT NULL CHECK (delivered_quantity >= 0)
);
CREATE INDEX idx_delivery_items_delivery_id ON public.delivery_items(delivery_id);

-- returns: standalone field events now (no shop/order/payable linkage since
-- dues aren't tracked digitally).
CREATE TABLE public.returns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES public.products(id),
  unit_type public.unit_type NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  condition public.return_condition NOT NULL,
  reason TEXT,
  return_date DATE NOT NULL DEFAULT current_date,
  recorded_by UUID NOT NULL REFERENCES public.profiles(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_returns_return_date ON public.returns(return_date);

CREATE TRIGGER daily_summaries_updated_at BEFORE UPDATE ON public.daily_summaries
FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();

-- ============================================================================
-- Helper functions
-- ============================================================================
CREATE OR REPLACE FUNCTION public.is_paired_deliveryman(p_salesman_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE user_id = p_salesman_id AND paired_deliveryman_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.can_view_summary(p_summary_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.daily_summaries s
    WHERE s.id = p_summary_id
      AND (
        public.current_role() = 'owner'
        OR s.salesman_id = auth.uid()
        OR public.is_paired_deliveryman(s.salesman_id)
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.delivery_summary_id(p_delivery_id UUID)
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT summary_id FROM public.deliveries WHERE id = p_delivery_id;
$$;

-- ============================================================================
-- RLS — all writes happen through RPCs (next migration); tables here are
-- read-only to clients.
-- ============================================================================
ALTER TABLE public.daily_summaries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.daily_summaries FROM authenticated;
GRANT SELECT ON public.daily_summaries TO authenticated;

CREATE POLICY daily_summaries_select ON public.daily_summaries
  FOR SELECT TO authenticated
  USING (
    public.current_role() = 'owner'
    OR salesman_id = (SELECT auth.uid())
    OR public.is_paired_deliveryman(salesman_id)
  );

ALTER TABLE public.daily_summary_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.daily_summary_items FROM authenticated;
GRANT SELECT ON public.daily_summary_items TO authenticated;

CREATE POLICY daily_summary_items_select ON public.daily_summary_items
  FOR SELECT TO authenticated USING (public.can_view_summary(summary_id));

ALTER TABLE public.deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.deliveries FROM authenticated;
GRANT SELECT ON public.deliveries TO authenticated;

CREATE POLICY deliveries_select ON public.deliveries
  FOR SELECT TO authenticated USING (public.can_view_summary(summary_id));

ALTER TABLE public.delivery_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.delivery_items FROM authenticated;
GRANT SELECT ON public.delivery_items TO authenticated;

CREATE POLICY delivery_items_select ON public.delivery_items
  FOR SELECT TO authenticated
  USING (public.can_view_summary(public.delivery_summary_id(delivery_id)));

ALTER TABLE public.returns ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.returns FROM authenticated;
GRANT SELECT ON public.returns TO authenticated;

CREATE POLICY returns_select ON public.returns
  FOR SELECT TO authenticated
  USING (public.current_role() = 'owner' OR recorded_by = (SELECT auth.uid()));

-- ============================================================================
-- Audit logging (FR-12)
-- ============================================================================
CREATE TRIGGER audit_daily_summaries AFTER INSERT OR UPDATE OR DELETE ON public.daily_summaries
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
CREATE TRIGGER audit_deliveries AFTER INSERT OR UPDATE OR DELETE ON public.deliveries
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
CREATE TRIGGER audit_returns AFTER INSERT OR UPDATE OR DELETE ON public.returns
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
