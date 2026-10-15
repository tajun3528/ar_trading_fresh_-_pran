-- The app's default accent moves from the original green to the brand indigo
-- carried through from the sign-in screen, so an account that never opens
-- Profile still gets the branded look.
--
-- Only the default changes: anyone who has actually chosen an accent keeps it.
ALTER TABLE public.user_preferences ALTER COLUMN accent SET DEFAULT 'indigo';
