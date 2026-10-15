-- The app followed the operating system by default, so anyone whose Windows
-- is in dark mode got a dark app they never asked for — and the owner wants
-- the off-white page back.
--
-- Light is now the default. Dark and "follow the system" are still there in
-- Profile for anyone who prefers them, and anyone who has already chosen a
-- theme keeps their choice.
ALTER TABLE public.user_preferences ALTER COLUMN theme_mode SET DEFAULT 'light';
