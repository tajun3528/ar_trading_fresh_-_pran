-- ============================================================================
-- What actually sold, by product, by month.
--
-- The Profit page answers "how did the month do" in one number. It can't
-- answer "which items are moving" or "where am I selling below the price the
-- company charges me" — and that second question is the one that costs money
-- quietly, because an order still looks fine in the totals while one line
-- underneath it loses on every piece.
--
-- Grain is (company, month, product, unit) rather than one row per product:
-- a carton can sell above ETP in the same month the loose pieces sell below
-- it, and netting those together would hide exactly the line worth finding.
-- ============================================================================
CREATE OR REPLACE VIEW public.monthly_product_sales
WITH (security_invoker = true) AS
SELECT
  lp.company_id,
  lp.month,
  lp.product_id,
  p.name                                     AS product_name,
  p.category_id,
  lp.unit_type,
  SUM(lp.quantity)                           AS quantity,
  SUM(lp.revenue)                            AS revenue,
  SUM(lp.dp_value)                           AS basis_value,
  SUM(lp.profit1)                            AS margin,
  SUM(lp.profit2)                            AS commission,
  CASE WHEN SUM(lp.quantity) > 0
    THEN round(SUM(lp.revenue) / SUM(lp.quantity), 4) END   AS avg_selling_price,
  CASE WHEN SUM(lp.quantity) > 0 AND SUM(lp.dp_value) IS NOT NULL
    THEN round(SUM(lp.dp_value) / SUM(lp.quantity), 4) END  AS avg_basis_price,
  count(DISTINCT lp.summary_id)              AS orders,
  -- A line with no cost price contributes nothing to basis_value or margin,
  -- which would read as a healthy sale rather than an unknown one. Surface it
  -- so the report can say so instead of quietly understating the cost.
  count(*) FILTER (WHERE lp.dp_price IS NULL) AS lines_missing_basis
FROM public.delivered_line_profit lp
JOIN public.products p ON p.id = lp.product_id
GROUP BY lp.company_id, lp.month, lp.product_id, p.name, p.category_id, lp.unit_type;

GRANT SELECT ON public.monthly_product_sales TO authenticated;
