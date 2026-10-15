-- ============================================================================
-- Changing your own password.
--
-- InsForge's auth API has no in-session password change: the only route is an
-- emailed reset link. Three of this business's five accounts have no email at
-- all — they sign in with a mobile number — so for them a forgotten or shared
-- password could never be changed by anyone.
--
-- Passwords are bcrypt (`$2b$10$`) and pgcrypto is installed, so both checking
-- and setting can be done here. One wrinkle: pgcrypto only recognises the
-- `$2a$` identifier, while InsForge writes `$2b$`. The two differ only in
-- handling of passwords past 72 bytes; below that the algorithm is identical,
-- so the prefix is swapped for the comparison and swapped back when storing.
-- Verified against a real InsForge-written hash: the right password matches
-- and a wrong one does not.
-- ============================================================================

-- Rejects anything that is not the bcrypt this relies on, rather than silently
-- mis-handling some future scheme.
CREATE OR REPLACE FUNCTION public._bcrypt_as_2a(p_hash TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, public
AS $fn$
BEGIN
  IF p_hash IS NULL OR length(p_hash) <> 60 OR left(p_hash, 2) <> '$2' THEN
    RAISE EXCEPTION 'this account does not use a password that can be changed here';
  END IF;
  RETURN '$2a$' || substring(p_hash from 5);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.change_my_password(p_current TEXT, p_new TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $fn$
DECLARE
  v_hash TEXT;
  v_as_2a TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;
  IF p_new IS NULL OR length(p_new) < 6 THEN
    RAISE EXCEPTION 'the new password must be at least 6 characters';
  END IF;
  -- bcrypt silently ignores anything past 72 bytes, which would make a long
  -- password weaker than it looks.
  IF octet_length(p_new) > 72 THEN
    RAISE EXCEPTION 'the new password is too long — 72 characters at most';
  END IF;
  IF p_current IS NULL OR p_current = '' THEN
    RAISE EXCEPTION 'enter your current password';
  END IF;

  SELECT password INTO v_hash FROM auth.users WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'account not found';
  END IF;

  v_as_2a := public._bcrypt_as_2a(v_hash);
  IF crypt(p_current, v_as_2a) <> v_as_2a THEN
    RAISE EXCEPTION 'your current password is not right';
  END IF;
  IF crypt(p_new, v_as_2a) = v_as_2a THEN
    RAISE EXCEPTION 'the new password is the same as the current one';
  END IF;

  -- Stored back as $2b$ so it is byte-for-byte what InsForge itself writes.
  UPDATE auth.users
     SET password = '$2b$' || substring(crypt(p_new, gen_salt('bf', 10)) from 5),
         updated_at = now()
   WHERE id = auth.uid();
END;
$fn$;
REVOKE ALL ON FUNCTION public.change_my_password(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.change_my_password(TEXT, TEXT) TO authenticated;

-- ============================================================================
-- owner_reset_password — the way back in when someone forgets.
--
-- Most accounts here have no email, so there is no reset link to send. The
-- owner is the recovery path, exactly as they are for approving accounts.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.owner_reset_password(p_user_id UUID, p_new TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $fn$
BEGIN
  IF public.current_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'only an owner can reset someone else''s password';
  END IF;
  IF p_new IS NULL OR length(p_new) < 6 THEN
    RAISE EXCEPTION 'the new password must be at least 6 characters';
  END IF;
  IF octet_length(p_new) > 72 THEN
    RAISE EXCEPTION 'the new password is too long — 72 characters at most';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE user_id = p_user_id) THEN
    RAISE EXCEPTION 'that account does not exist';
  END IF;

  UPDATE auth.users
     SET password = '$2b$' || substring(crypt(p_new, gen_salt('bf', 10)) from 5),
         updated_at = now()
   WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'that account has no sign-in to reset';
  END IF;
END;
$fn$;
REVOKE ALL ON FUNCTION public.owner_reset_password(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_reset_password(UUID, TEXT) TO authenticated;
