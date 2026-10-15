-- Adding p_salesman_id created a second submit_daily_summary alongside the
-- original four-argument one. Postgres keeps both, and a call that matches
-- neither exactly fails as ambiguous — so the superseded one has to go.
DROP FUNCTION IF EXISTS public.submit_daily_summary(JSONB, UUID, DATE, NUMERIC);
