-- Fix: NEW.id / OLD.id fails at runtime ("record has no field") on tables
-- without an `id` column — profiles uses `user_id` as its primary key.
-- Look the key up dynamically through JSONB instead of a static field access.
CREATE OR REPLACE FUNCTION public.audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_row JSONB;
  v_record_id UUID;
BEGIN
  v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  v_record_id := COALESCE(v_row->>'id', v_row->>'user_id')::UUID;

  INSERT INTO public.audit_log (user_id, action_type, table_name, record_id, details)
  VALUES (auth.uid(), TG_OP, TG_TABLE_NAME, v_record_id, v_row);

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;
