-- ============================================================================
-- Who and where is actually earning.
--
-- monthly_profit_history answers "how did the month do" for a whole company.
-- It can't say which salesman carried it or which route is worth the fuel,
-- and those are different questions with different answers: a salesman can
-- post the biggest sales and the thinnest profit in the same month by
-- discounting, and a route can look busy while barely covering its own
-- commission.
--
-- Both grains come off summary_profit, which already carries salesman, route
-- and the order's own commission — so these can never disagree with the
-- Profit page.
-- ============================================================================
CREATE OR REPLACE VIEW public.monthly_salesman_profit
WITH (security_invoker = true) AS
SELECT
  sp.company_id,
  sp.month,
  sp.salesman_id,
  count(*)                                AS orders,
  COALESCE(SUM(sp.revenue), 0)            AS revenue,
  COALESCE(SUM(sp.dp_value), 0)           AS basis_value,
  COALESCE(SUM(sp.profit1), 0)            AS profit1,
  COALESCE(SUM(sp.profit2), 0)            AS profit2,
  COALESCE(SUM(sp.commission_amount), 0)  AS commission_total,
  COALESCE(SUM(sp.order_profit), 0)       AS orders_profit,
  -- What the owner keeps per taka sold. The comparison that matters: two
  -- salesmen with the same sales can hand over very different profit.
  CASE WHEN COALESCE(SUM(sp.revenue), 0) > 0
    THEN round(COALESCE(SUM(sp.order_profit), 0) / SUM(sp.revenue) * 100, 2) END AS profit_margin_percent,
  COALESCE(SUM(sp.lines_missing_price), 0) AS lines_missing_price,
  COALESCE(SUM(sp.lines_missing_dp), 0)    AS lines_missing_basis
FROM public.summary_profit sp
GROUP BY sp.company_id, sp.month, sp.salesman_id;

GRANT SELECT ON public.monthly_salesman_profit TO authenticated;

CREATE OR REPLACE VIEW public.monthly_route_profit
WITH (security_invoker = true) AS
SELECT
  sp.company_id,
  sp.month,
  sp.route_id,
  count(*)                                AS orders,
  count(DISTINCT sp.salesman_id)          AS salesmen,
  COALESCE(SUM(sp.revenue), 0)            AS revenue,
  COALESCE(SUM(sp.dp_value), 0)           AS basis_value,
  COALESCE(SUM(sp.profit1), 0)            AS profit1,
  COALESCE(SUM(sp.profit2), 0)            AS profit2,
  COALESCE(SUM(sp.commission_amount), 0)  AS commission_total,
  COALESCE(SUM(sp.order_profit), 0)       AS orders_profit,
  CASE WHEN COALESCE(SUM(sp.revenue), 0) > 0
    THEN round(COALESCE(SUM(sp.order_profit), 0) / SUM(sp.revenue) * 100, 2) END AS profit_margin_percent,
  -- Average order size says whether a route is many small drops or a few
  -- big ones — the same revenue means a very different day for the van.
  CASE WHEN count(*) > 0
    THEN round(COALESCE(SUM(sp.revenue), 0) / count(*), 2) END AS avg_order_value
FROM public.summary_profit sp
GROUP BY sp.company_id, sp.month, sp.route_id;

GRANT SELECT ON public.monthly_route_profit TO authenticated;
