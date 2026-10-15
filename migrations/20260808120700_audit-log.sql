-- ============================================================================
-- audit_log — FR-12: user, action, affected record, timestamp for every
-- create/update/delete. Insert-only, owner-only read, no client writes at all
-- (only the trigger function, running as its owner, ever inserts into it).
-- ============================================================================
CREATE TABLE public.audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id),
  action_type TEXT NOT NULL,
  table_name TEXT NOT NULL,
  record_id UUID,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  details JSONB
);
CREATE INDEX idx_audit_log_occurred_at ON public.audit_log(occurred_at);
CREATE INDEX idx_audit_log_table_name ON public.audit_log(table_name);

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.audit_log FROM anon, authenticated;
GRANT SELECT ON public.audit_log TO authenticated;

CREATE POLICY audit_log_owner_select ON public.audit_log
  FOR SELECT TO authenticated
  USING (public.current_role() = 'owner');

CREATE OR REPLACE FUNCTION public.audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_record_id UUID;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_record_id := OLD.id;
  ELSE
    v_record_id := NEW.id;
  END IF;

  INSERT INTO public.audit_log (user_id, action_type, table_name, record_id, details)
  VALUES (
    auth.uid(),
    TG_OP,
    TG_TABLE_NAME,
    v_record_id,
    CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER audit_categories AFTER INSERT OR UPDATE OR DELETE ON public.categories FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
CREATE TRIGGER audit_products AFTER INSERT OR UPDATE OR DELETE ON public.products FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
CREATE TRIGGER audit_product_units AFTER INSERT OR UPDATE OR DELETE ON public.product_units FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
CREATE TRIGGER audit_product_batches AFTER INSERT OR UPDATE OR DELETE ON public.product_batches FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
CREATE TRIGGER audit_routes AFTER INSERT OR UPDATE OR DELETE ON public.routes FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
CREATE TRIGGER audit_shops AFTER INSERT OR UPDATE OR DELETE ON public.shops FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
CREATE TRIGGER audit_stock_ins AFTER INSERT OR UPDATE OR DELETE ON public.stock_ins FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
CREATE TRIGGER audit_orders AFTER INSERT OR UPDATE OR DELETE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
CREATE TRIGGER audit_deliveries AFTER INSERT OR UPDATE OR DELETE ON public.deliveries FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
CREATE TRIGGER audit_returns AFTER INSERT OR UPDATE OR DELETE ON public.returns FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
CREATE TRIGGER audit_payments AFTER INSERT OR UPDATE OR DELETE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
CREATE TRIGGER audit_profiles AFTER INSERT OR UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();
