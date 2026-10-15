-- The app is gaining animation throughout. Motion helps most people read a
-- change, but it genuinely hurts some — and on a tired phone it can make the
-- app feel slower rather than livelier. So it has to be switchable off, per
-- person, alongside the other appearance settings.
--
-- Off by default: the animation is the point of the redesign.
ALTER TABLE public.user_preferences
  ADD COLUMN reduce_motion BOOLEAN NOT NULL DEFAULT false;

-- Re-declared to carry the new field. Everything else is unchanged.
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
    reduce_motion            = COALESCE((p_patch->>'reduce_motion')::BOOLEAN, p.reduce_motion),
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
