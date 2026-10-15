-- ============================================================================
-- Per-person settings.
--
-- The app is one size for everyone: 88% text, compact density, one accent,
-- everybody lands on their role's dashboard, and everybody gets every
-- notification. None of that suits a warehouse owner on a desktop and a
-- salesman squinting at a phone in a market equally.
--
-- Kept in the database rather than in the browser so a person's settings
-- follow them to whatever device they sign in on — the app is online-only
-- anyway, so there is nothing to gain from local-only storage.
-- ============================================================================
CREATE TABLE public.user_preferences (
  user_id UUID PRIMARY KEY REFERENCES public.profiles(user_id) ON DELETE CASCADE,

  -- Appearance
  theme_mode TEXT NOT NULL DEFAULT 'system'
    CHECK (theme_mode IN ('system', 'light', 'dark')),
  text_scale NUMERIC(3,2) NOT NULL DEFAULT 0.88
    CHECK (text_scale >= 0.75 AND text_scale <= 1.30),
  density TEXT NOT NULL DEFAULT 'compact'
    CHECK (density IN ('compact', 'standard', 'comfortable')),
  accent TEXT NOT NULL DEFAULT 'green'
    CHECK (accent IN ('green', 'indigo', 'teal', 'plum', 'slate')),

  -- Where signing in drops you. NULL keeps the role's own home page.
  landing_route TEXT,

  -- Which notifications reach the bell.
  notify_awaiting_approval BOOLEAN NOT NULL DEFAULT true,
  notify_rejected BOOLEAN NOT NULL DEFAULT true,
  notify_approved BOOLEAN NOT NULL DEFAULT true,

  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_preferences TO authenticated;

CREATE TRIGGER user_preferences_updated_at BEFORE UPDATE ON public.user_preferences
FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();

-- Yours and nobody else's — not even the owner's business.
CREATE POLICY user_preferences_own ON public.user_preferences
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

-- ============================================================================
-- save_my_preferences — upsert the caller's row from a partial patch, so the
-- screen can save one toggle without resending every other setting.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.save_my_preferences(p_patch JSONB)
RETURNS public.user_preferences
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_row public.user_preferences;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;

  INSERT INTO public.user_preferences (user_id) VALUES (auth.uid())
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE public.user_preferences p SET
    theme_mode               = COALESCE(p_patch->>'theme_mode', p.theme_mode),
    text_scale               = COALESCE((p_patch->>'text_scale')::NUMERIC, p.text_scale),
    density                  = COALESCE(p_patch->>'density', p.density),
    accent                   = COALESCE(p_patch->>'accent', p.accent),
    -- landing_route is nullable and "back to my role's home" is a real
    -- choice, so an explicit JSON null has to clear it rather than be
    -- treated as "unchanged".
    landing_route            = CASE WHEN p_patch ? 'landing_route'
                                    THEN NULLIF(p_patch->>'landing_route', '')
                                    ELSE p.landing_route END,
    notify_awaiting_approval = COALESCE((p_patch->>'notify_awaiting_approval')::BOOLEAN, p.notify_awaiting_approval),
    notify_rejected          = COALESCE((p_patch->>'notify_rejected')::BOOLEAN, p.notify_rejected),
    notify_approved          = COALESCE((p_patch->>'notify_approved')::BOOLEAN, p.notify_approved),
    updated_at               = now()
  WHERE p.user_id = auth.uid()
  RETURNING p.* INTO v_row;

  RETURN v_row;
END;
$$;
GRANT EXECUTE ON FUNCTION public.save_my_preferences(JSONB) TO authenticated;

-- ============================================================================
-- update_my_profile — name / mobile / email only.
--
-- profiles is already writable by its owner under RLS, but going through a
-- function keeps the editable set explicit: role, status, company and pairing
-- are the owner's to set and must not be reachable from a settings screen.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_my_profile(
  p_name TEXT,
  p_mobile TEXT,
  p_email TEXT DEFAULT NULL
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_row public.profiles;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not signed in';
  END IF;
  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RAISE EXCEPTION 'name cannot be empty';
  END IF;
  IF p_mobile IS NULL OR btrim(p_mobile) = '' THEN
    RAISE EXCEPTION 'mobile number cannot be empty';
  END IF;

  -- The mobile number is how people sign in, so it has to stay unique.
  IF EXISTS (
    SELECT 1 FROM public.profiles
     WHERE mobile = btrim(p_mobile) AND user_id <> auth.uid()
  ) THEN
    RAISE EXCEPTION 'that mobile number already belongs to another account';
  END IF;

  UPDATE public.profiles SET
    name       = btrim(p_name),
    mobile     = btrim(p_mobile),
    email      = NULLIF(btrim(COALESCE(p_email, '')), ''),
    updated_at = now()
  WHERE user_id = auth.uid()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
GRANT EXECUTE ON FUNCTION public.update_my_profile(TEXT, TEXT, TEXT) TO authenticated;
