-- ============================================================================
-- Fix: InsForge's /api/auth/users signup endpoint only ever stores the plain
-- `name` field into auth.users.profile — there is no way to pass custom
-- fields like mobile/role through signUp() itself. Switch to a two-step flow:
--   1) POST /api/auth/users (email, password, name) — creates the auth user;
--      handle_new_user() stub-creates a minimal, incomplete profiles row.
--   2) RPC complete_profile(name, mobile, role, email) — the now-authenticated
--      client fills in the real identity fields exactly once.
-- ============================================================================

ALTER TABLE public.profiles ALTER COLUMN mobile DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  INSERT INTO public.profiles (user_id, name, mobile, email, role, status)
  VALUES (
    NEW.id,
    COALESCE(NEW.profile->>'name', ''),
    NULL,
    NULL,
    'salesman',
    'pending'
  )
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Role/status become owner-only to change only once the profile has actually
-- been completed (mobile set) — complete_profile() needs one free role write
-- for the caller's own brand-new row.
CREATE OR REPLACE FUNCTION public.guard_profile_privileges()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF (NEW.role IS DISTINCT FROM OLD.role OR NEW.status IS DISTINCT FROM OLD.status)
     AND OLD.mobile IS NOT NULL
     AND public.current_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'only an owner can change role or status';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_profile(
  p_name TEXT,
  p_mobile TEXT,
  p_role public.user_role,
  p_email TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_updated INTEGER;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF p_role = 'owner' THEN
    RAISE EXCEPTION 'cannot self-assign the owner role';
  END IF;
  IF p_mobile IS NULL OR length(trim(p_mobile)) = 0 THEN
    RAISE EXCEPTION 'mobile is required';
  END IF;

  UPDATE public.profiles
    SET name = p_name, mobile = p_mobile, role = p_role, email = p_email
    WHERE user_id = auth.uid() AND mobile IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RAISE EXCEPTION 'profile already completed or not found';
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.complete_profile(TEXT, TEXT, public.user_role, TEXT) TO authenticated;
