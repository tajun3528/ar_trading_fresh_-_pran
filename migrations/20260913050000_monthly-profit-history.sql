-- ============================================================================
-- Profit for every month, not one month at a time.
--
-- monthly_profit() answered for a single month, which suits the Profit page's
-- month picker but can't show a run of months side by side. This view carries
-- the same arithmetic across every month that has a delivered order, and
-- monthly_profit() now reads from it so the two can never disagree.
-- ============================================================================
CREATE OR REPLACE VIEW public.monthly_profit_history
WITH (security_invoker = true) AS
WITH totals AS (
  SELECT
    sp.company_id,
    sp.month,
    COALESCE(SUM(sp.revenue), 0)           AS revenue,
    COALESCE(SUM(sp.dp_value), 0)          AS dp_value,
    COALESCE(SUM(sp.profit1), 0)           AS profit1,
    COALESCE(SUM(sp.profit2), 0)           AS profit2,
    COALESCE(SUM(sp.commission_amount), 0) AS commission_total,
    COALESCE(SUM(sp.order_profit), 0)      AS orders_profit,
    count(*)                               AS orders
  FROM public.summary_profit sp
  GROUP BY sp.company_id, sp.month
)
SELECT
  t.company_id,
  t.month,
  t.revenue,
  t.dp_value,
  t.profit1,
  t.profit2,
  t.commission_total,
  t.orders_profit,
  t.orders,
  mt.target_amount,
  COALESCE(mt.bonus_percent, 0) AS bonus_percent,
  (mt.target_amount IS NOT NULL AND t.dp_value >= mt.target_amount) AS target_met,
  CASE
    WHEN mt.target_amount IS NOT NULL AND t.dp_value >= mt.target_amount
      THEN round(t.dp_value * COALESCE(mt.bonus_percent, 0) / 100.0, 2)
    ELSE 0
  END AS bonus_amount,
  t.orders_profit + CASE
    WHEN mt.target_amount IS NOT NULL AND t.dp_value >= mt.target_amount
      THEN round(t.dp_value * COALESCE(mt.bonus_percent, 0) / 100.0, 2)
    ELSE 0
  END AS net_profit
FROM totals t
LEFT JOIN public.monthly_targets mt
  ON mt.company_id = t.company_id AND mt.month = t.month;

GRANT SELECT ON public.monthly_profit_history TO authenticated;

-- ============================================================================
-- monthly_profit — the same figures for one month, now a filter over the view
-- rather than a second copy of the arithmetic.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.monthly_profit(p_month DATE, p_company_id UUID DEFAULT NULL)
RETURNS TABLE (
  company_id UUID,
  month DATE,
  revenue NUMERIC,
  dp_value NUMERIC,
  profit1 NUMERIC,
  profit2 NUMERIC,
  commission_total NUMERIC,
  orders_profit NUMERIC,
  target_amount NUMERIC,
  bonus_percent NUMERIC,
  target_met BOOLEAN,
  bonus_amount NUMERIC,
  net_profit NUMERIC
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT h.company_id, h.month, h.revenue, h.dp_value, h.profit1, h.profit2,
         h.commission_total, h.orders_profit, h.target_amount, h.bonus_percent,
         h.target_met, h.bonus_amount, h.net_profit
    FROM public.monthly_profit_history h
   WHERE h.month = date_trunc('month', p_month)::date
     AND (p_company_id IS NULL OR h.company_id = p_company_id);
$$;
