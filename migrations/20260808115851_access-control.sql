-- ============================================================================
-- Helper functions (SECURITY DEFINER, pinned search_path — see access-control
-- reference to avoid recursive-RLS and name-resolution issues)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.current_role()
RETURNS public.user_role
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT role FROM public.profiles WHERE user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.current_status()
RETURNS public.user_status
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT status FROM public.profiles WHERE user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.is_route_salesman(p_route_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.routes WHERE id = p_route_id AND salesman_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.is_route_deliveryman(p_route_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.routes WHERE id = p_route_id AND deliveryman_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.shop_route_id(p_shop_id UUID)
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT route_id FROM public.shops WHERE id = p_shop_id;
$$;

CREATE OR REPLACE FUNCTION public.can_view_order(p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id = p_order_id
      AND (
        public.current_role() = 'owner'
        OR o.salesman_id = auth.uid()
        OR public.is_route_deliveryman(public.shop_route_id(o.shop_id))
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.delivery_order_id(p_delivery_id UUID)
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT order_id FROM public.deliveries WHERE id = p_delivery_id;
$$;

-- Converts any unit quantity for a product into whole pieces using that
-- product's fixed conversion factors (FR-3.1/3.3).
CREATE OR REPLACE FUNCTION public.to_pieces(p_product_id UUID, p_unit public.unit_type, p_qty INTEGER)
RETURNS INTEGER
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT CASE p_unit
    WHEN 'pcs' THEN p_qty
    WHEN 'jar' THEN p_qty * pcs_per_jar
    WHEN 'carton' THEN p_qty * pcs_per_jar * jars_per_carton
  END
  FROM public.products WHERE id = p_product_id;
$$;

-- ============================================================================
-- Sign-up hook: create the profile row (status always starts 'pending' so an
-- Owner must approve every new account per FR-1.5).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_role public.user_role;
BEGIN
  BEGIN
    v_role := COALESCE(NEW.profile->>'role', 'salesman')::public.user_role;
  EXCEPTION WHEN invalid_text_representation THEN
    v_role := 'salesman';
  END;

  INSERT INTO public.profiles (user_id, name, mobile, email, role, status)
  VALUES (
    NEW.id,
    COALESCE(NEW.profile->>'name', ''),
    NEW.profile->>'mobile',
    NEW.profile->>'real_email',
    v_role,
    'pending'
  )
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Only an owner may change role/status; RLS USING/WITH CHECK can't diff
-- OLD vs NEW so this needs a trigger guard (see integrity reference).
CREATE OR REPLACE FUNCTION public.guard_profile_privileges()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF (NEW.role IS DISTINCT FROM OLD.role OR NEW.status IS DISTINCT FROM OLD.status)
     AND public.current_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'only an owner can change role or status';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_guard_privileges
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.guard_profile_privileges();

-- ============================================================================
-- Lock down anon entirely — every module requires authentication (NFR-1).
-- ============================================================================
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;

-- ============================================================================
-- profiles
-- ============================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.profiles FROM authenticated;
GRANT SELECT, UPDATE ON public.profiles TO authenticated;

CREATE POLICY profiles_select ON public.profiles
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.current_role() = 'owner');

CREATE POLICY profiles_update ON public.profiles
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.current_role() = 'owner')
  WITH CHECK (user_id = (SELECT auth.uid()) OR public.current_role() = 'owner');

-- ============================================================================
-- categories (owner-managed, everyone can read)
-- ============================================================================
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.categories TO authenticated;

CREATE POLICY categories_select ON public.categories
  FOR SELECT TO authenticated USING (true);

CREATE POLICY categories_write ON public.categories
  FOR ALL TO authenticated
  USING (public.current_role() = 'owner')
  WITH CHECK (public.current_role() = 'owner');

-- ============================================================================
-- products (owner-managed; everyone sees active ones, owner sees all)
-- ============================================================================
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.products TO authenticated;

CREATE POLICY products_select ON public.products
  FOR SELECT TO authenticated
  USING (is_active OR public.current_role() = 'owner');

CREATE POLICY products_write ON public.products
  FOR ALL TO authenticated
  USING (public.current_role() = 'owner')
  WITH CHECK (public.current_role() = 'owner');

-- ============================================================================
-- product_units (owner-managed; everyone can read prices to book orders)
-- ============================================================================
ALTER TABLE public.product_units ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.product_units TO authenticated;

CREATE POLICY product_units_select ON public.product_units
  FOR SELECT TO authenticated USING (true);

CREATE POLICY product_units_write ON public.product_units
  FOR ALL TO authenticated
  USING (public.current_role() = 'owner')
  WITH CHECK (public.current_role() = 'owner');

-- ============================================================================
-- routes (owner-managed; salesman/deliveryman can see only their own route)
-- ============================================================================
ALTER TABLE public.routes ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.routes TO authenticated;

CREATE POLICY routes_select ON public.routes
  FOR SELECT TO authenticated
  USING (
    public.current_role() = 'owner'
    OR salesman_id = (SELECT auth.uid())
    OR deliveryman_id = (SELECT auth.uid())
  );

CREATE POLICY routes_write ON public.routes
  FOR ALL TO authenticated
  USING (public.current_role() = 'owner')
  WITH CHECK (public.current_role() = 'owner');

-- ============================================================================
-- shops (owner-managed; salesman/deliveryman scoped to their route — FR-4.5/4.6)
-- ============================================================================
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.shops TO authenticated;

CREATE POLICY shops_select ON public.shops
  FOR SELECT TO authenticated
  USING (
    public.current_role() = 'owner'
    OR public.is_route_salesman(route_id)
    OR public.is_route_deliveryman(route_id)
  );

CREATE POLICY shops_write ON public.shops
  FOR ALL TO authenticated
  USING (public.current_role() = 'owner')
  WITH CHECK (public.current_role() = 'owner');

-- ============================================================================
-- stock (read-only to clients; all mutation happens through RPCs below)
-- ============================================================================
ALTER TABLE public.stock ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.stock FROM authenticated;
GRANT SELECT ON public.stock TO authenticated;

CREATE POLICY stock_select ON public.stock
  FOR SELECT TO authenticated USING (true);

-- ============================================================================
-- stock_ins (owner-only visibility; writes only via stock_in() RPC)
-- ============================================================================
ALTER TABLE public.stock_ins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.stock_ins FROM authenticated;
GRANT SELECT ON public.stock_ins TO authenticated;

CREATE POLICY stock_ins_select ON public.stock_ins
  FOR SELECT TO authenticated USING (public.current_role() = 'owner');

-- ============================================================================
-- orders / order_items (writes only via book_order/edit_order/cancel_order/
-- confirm_delivery RPCs)
-- ============================================================================
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.orders FROM authenticated;
GRANT SELECT ON public.orders TO authenticated;

CREATE POLICY orders_select ON public.orders
  FOR SELECT TO authenticated
  USING (
    public.current_role() = 'owner'
    OR salesman_id = (SELECT auth.uid())
    OR public.is_route_deliveryman(public.shop_route_id(shop_id))
  );

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.order_items FROM authenticated;
GRANT SELECT ON public.order_items TO authenticated;

CREATE POLICY order_items_select ON public.order_items
  FOR SELECT TO authenticated USING (public.can_view_order(order_id));

-- ============================================================================
-- deliveries / delivery_items (writes only via confirm_delivery() RPC)
-- ============================================================================
ALTER TABLE public.deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.deliveries FROM authenticated;
GRANT SELECT ON public.deliveries TO authenticated;

CREATE POLICY deliveries_select ON public.deliveries
  FOR SELECT TO authenticated USING (public.can_view_order(order_id));

ALTER TABLE public.delivery_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.delivery_items FROM authenticated;
GRANT SELECT ON public.delivery_items TO authenticated;

CREATE POLICY delivery_items_select ON public.delivery_items
  FOR SELECT TO authenticated
  USING (public.can_view_order(public.delivery_order_id(delivery_id)));

-- ============================================================================
-- returns (writes only via record_return() RPC)
-- ============================================================================
ALTER TABLE public.returns ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.returns FROM authenticated;
GRANT SELECT ON public.returns TO authenticated;

CREATE POLICY returns_select ON public.returns
  FOR SELECT TO authenticated
  USING (
    public.current_role() = 'owner'
    OR recorded_by = (SELECT auth.uid())
    OR public.is_route_salesman(public.shop_route_id(shop_id))
    OR public.is_route_deliveryman(public.shop_route_id(shop_id))
  );

-- ============================================================================
-- payments (writes only via record_payment() RPC)
-- ============================================================================
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payments FROM authenticated;
GRANT SELECT ON public.payments TO authenticated;

CREATE POLICY payments_select ON public.payments
  FOR SELECT TO authenticated
  USING (
    public.current_role() = 'owner'
    OR collected_by = (SELECT auth.uid())
    OR public.is_route_salesman(public.shop_route_id(shop_id))
    OR public.is_route_deliveryman(public.shop_route_id(shop_id))
  );
