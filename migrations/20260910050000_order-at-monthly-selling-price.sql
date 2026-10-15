-- ============================================================================
-- Orders are now valued at the salesman's own monthly selling price rather
-- than the catalog's trade price, so a summary's line totals and grand total
-- are what the shops are actually billed.
--
-- Where a salesman hasn't set a price for that month, the line falls back to
-- the catalog TP: a salesman in the field at the start of a month must never
-- be blocked from submitting an order. The order screen marks those lines so
-- the fallback is visible before submitting.
--
-- The month used is the delivery month, matching how profit is reported.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.order_unit_price(
  p_summary_id UUID,
  p_product_id UUID,
  p_unit_type public.unit_type
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_salesman_id UUID;
  v_month DATE;
  v_price NUMERIC(12,2);
BEGIN
  SELECT salesman_id, date_trunc('month', delivery_date)::date
    INTO v_salesman_id, v_month
    FROM public.daily_summaries WHERE id = p_summary_id;

  SELECT selling_price INTO v_price
    FROM public.salesman_monthly_prices
   WHERE salesman_id = v_salesman_id
     AND product_id = p_product_id
     AND unit_type = p_unit_type
     AND month = v_month;

  IF v_price IS NOT NULL THEN
    RETURN v_price;
  END IF;

  SELECT pu.price INTO v_price
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
   WHERE pu.product_id = p_product_id AND pu.unit_type = p_unit_type AND p.is_active;

  RETURN v_price;
END;
$$;

CREATE OR REPLACE FUNCTION public._upsert_summary_item(
  p_summary_id UUID,
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_quantity INTEGER,
  p_company_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_unit_price NUMERIC(12,2);
  v_existing_item_id UUID;
  v_existing_qty INTEGER;
  v_new_qty INTEGER;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = p_product_id AND company_id = p_company_id) THEN
    RAISE EXCEPTION 'product does not belong to your assigned company';
  END IF;

  v_unit_price := public.order_unit_price(p_summary_id, p_product_id, p_unit_type);
  IF v_unit_price IS NULL THEN
    RAISE EXCEPTION 'no active price for the given product/unit';
  END IF;

  SELECT id, quantity INTO v_existing_item_id, v_existing_qty
    FROM public.daily_summary_items
    WHERE summary_id = p_summary_id AND product_id = p_product_id AND unit_type = p_unit_type
    FOR UPDATE;

  IF v_existing_item_id IS NOT NULL THEN
    v_new_qty := v_existing_qty + p_quantity;
    UPDATE public.daily_summary_items
      SET quantity = v_new_qty, unit_price = v_unit_price, line_total = v_unit_price * v_new_qty
      WHERE id = v_existing_item_id;
  ELSE
    INSERT INTO public.daily_summary_items (summary_id, product_id, unit_type, quantity, unit_price, line_total)
    VALUES (p_summary_id, p_product_id, p_unit_type, p_quantity, v_unit_price, v_unit_price * p_quantity);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._set_summary_item(
  p_summary_id UUID,
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_quantity INTEGER,
  p_company_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_unit_price NUMERIC(12,2);
  v_existing_item_id UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = p_product_id AND company_id = p_company_id) THEN
    RAISE EXCEPTION 'product does not belong to your assigned company';
  END IF;

  SELECT id INTO v_existing_item_id
    FROM public.daily_summary_items
    WHERE summary_id = p_summary_id AND product_id = p_product_id AND unit_type = p_unit_type
    FOR UPDATE;

  IF p_quantity <= 0 THEN
    IF v_existing_item_id IS NOT NULL THEN
      DELETE FROM public.daily_summary_items WHERE id = v_existing_item_id;
    END IF;
    RETURN;
  END IF;

  v_unit_price := public.order_unit_price(p_summary_id, p_product_id, p_unit_type);
  IF v_unit_price IS NULL THEN
    RAISE EXCEPTION 'no active price for the given product/unit';
  END IF;

  IF v_existing_item_id IS NOT NULL THEN
    UPDATE public.daily_summary_items
      SET quantity = p_quantity, unit_price = v_unit_price, line_total = v_unit_price * p_quantity
      WHERE id = v_existing_item_id;
  ELSE
    INSERT INTO public.daily_summary_items (summary_id, product_id, unit_type, quantity, unit_price, line_total)
    VALUES (p_summary_id, p_product_id, p_unit_type, p_quantity, v_unit_price, v_unit_price * p_quantity);
  END IF;
END;
$$;

-- ============================================================================
-- Revenue now comes from what the line was actually billed at, not from a
-- fresh lookup of the month's price. The two are the same for a normally
-- priced order, but the stored figure is the honest one: it survives a later
-- price edit, and it covers lines that fell back to TP — which previously
-- dropped out of revenue entirely and understated profit.
-- ============================================================================
CREATE OR REPLACE VIEW public.delivered_line_profit
WITH (security_invoker = true) AS
SELECT
  di.id                                              AS delivery_item_id,
  d.id                                               AS delivery_id,
  s.id                                               AS summary_id,
  s.salesman_id,
  s.company_id,
  s.route_id,
  s.delivery_date,
  date_trunc('month', s.delivery_date)::date         AS month,
  dsi.product_id,
  dsi.unit_type,
  di.delivered_quantity                              AS quantity,
  dsi.unit_price                                     AS selling_price,
  public.product_unit_dp(dsi.product_id, dsi.unit_type) AS dp_price,
  di.delivered_quantity * dsi.unit_price             AS revenue,
  di.delivered_quantity * public.product_unit_dp(dsi.product_id, dsi.unit_type) AS dp_value,
  di.delivered_quantity * (dsi.unit_price - public.product_unit_dp(dsi.product_id, dsi.unit_type)) AS profit1,
  round(
    di.delivered_quantity * public.product_unit_dp(dsi.product_id, dsi.unit_type)
      * (c.commission_percent / 100.0), 2) AS profit2,
  -- Appended, not inserted: CREATE OR REPLACE VIEW cannot reorder columns.
  -- NULL here means the line was billed at TP because the salesman had set
  -- no price for that month — still real revenue, but worth flagging.
  smp.selling_price                                  AS monthly_price
FROM public.delivery_items di
JOIN public.deliveries d ON d.id = di.delivery_id
JOIN public.daily_summary_items dsi ON dsi.id = di.summary_item_id
JOIN public.daily_summaries s ON s.id = dsi.summary_id
JOIN public.companies c ON c.id = s.company_id
LEFT JOIN public.salesman_monthly_prices smp
  ON smp.salesman_id = s.salesman_id
 AND smp.product_id = dsi.product_id
 AND smp.unit_type = dsi.unit_type
 AND smp.month = date_trunc('month', s.delivery_date)::date
WHERE d.approval_status = 'approved'
  AND di.delivered_quantity > 0;

GRANT SELECT ON public.delivered_line_profit TO authenticated;

-- lines_missing_price now means "billed at TP for want of a monthly price"
-- rather than "missing from revenue" — the revenue itself is always counted.
CREATE OR REPLACE VIEW public.summary_profit
WITH (security_invoker = true) AS
SELECT
  s.id                                       AS summary_id,
  s.salesman_id,
  s.company_id,
  s.route_id,
  s.delivery_date,
  date_trunc('month', s.delivery_date)::date AS month,
  s.commission_amount,
  COALESCE(SUM(p.revenue), 0)                AS revenue,
  COALESCE(SUM(p.dp_value), 0)               AS dp_value,
  COALESCE(SUM(p.profit1), 0)                AS profit1,
  COALESCE(SUM(p.profit2), 0)                AS profit2,
  COALESCE(SUM(p.profit1), 0) + COALESCE(SUM(p.profit2), 0) - s.commission_amount AS order_profit,
  count(*) FILTER (WHERE p.monthly_price IS NULL) AS lines_missing_price,
  count(*) FILTER (WHERE p.dp_price IS NULL)      AS lines_missing_dp
FROM public.daily_summaries s
JOIN public.delivered_line_profit p ON p.summary_id = s.id
GROUP BY s.id, s.salesman_id, s.company_id, s.route_id, s.delivery_date, s.commission_amount;

GRANT SELECT ON public.summary_profit TO authenticated;
