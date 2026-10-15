-- ============================================================================
-- Profit tracking.
--
-- The business earns on a delivered order in two ways, per the Owner:
--   profit1 = (salesman's selling price − DP) × delivered qty
--   profit2 = (DP × delivered qty) × the company's commission %  (6%)
--   order profit = profit1 + profit2 − the salesman's own commission
-- and over a month:
--   net profit = Σ order profits + (month's DP-value × bonus %), the bonus
--   applying only once the month's target is reached.
--
-- Selling prices are entered by each salesman for each month, so the same
-- product can carry different prices for different salesmen — profit is
-- always computed against the price the salesman who sold it set.
-- ============================================================================

-- Per-carton counts for the two units that had no way to derive a DP. Same
-- shape as the existing pcs_per_carton/poli_per_carton settings.
ALTER TABLE public.products ADD COLUMN jar_per_carton INTEGER;
ALTER TABLE public.products ADD COLUMN box_per_carton INTEGER;

-- The cut the vendor pays on DP. Kept per company rather than hardcoded at
-- 6% so a second vendor on different terms doesn't need a code change.
ALTER TABLE public.companies ADD COLUMN commission_percent NUMERIC(5,2) NOT NULL DEFAULT 6;

-- ============================================================================
-- What one unit of a product costs the business. Carton is the anchor: every
-- smaller unit divides it by how many fit in a carton, matching how
-- per_pcs_dp_price already relates to dp_price in the vendor's own sheet.
-- NULL means "not derivable" — that unit is then left out of profit figures
-- rather than silently counted as free.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.product_unit_dp(p_product_id UUID, p_unit_type public.unit_type)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  p RECORD;
  v_per_carton INTEGER;
BEGIN
  SELECT dp_price, per_pcs_dp_price, pcs_per_carton, poli_per_carton, jar_per_carton, box_per_carton
    INTO p FROM public.products WHERE id = p_product_id;
  IF NOT FOUND OR p.dp_price IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_unit_type = 'carton' THEN
    RETURN p.dp_price;
  END IF;

  IF p_unit_type = 'pcs' AND p.per_pcs_dp_price IS NOT NULL THEN
    RETURN p.per_pcs_dp_price;
  END IF;

  v_per_carton := CASE p_unit_type
    WHEN 'pcs' THEN p.pcs_per_carton
    WHEN 'poli' THEN p.poli_per_carton
    WHEN 'jar' THEN p.jar_per_carton
    WHEN 'box' THEN p.box_per_carton
  END;
  IF v_per_carton IS NULL OR v_per_carton <= 0 THEN
    RETURN NULL;
  END IF;
  RETURN round(p.dp_price / v_per_carton, 4);
END;
$$;

-- ============================================================================
-- salesman_monthly_prices — what each salesman sells a unit for in a given
-- month. month is always stored as the first day of that month.
-- ============================================================================
CREATE TABLE public.salesman_monthly_prices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  salesman_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  unit_type public.unit_type NOT NULL,
  month DATE NOT NULL,
  selling_price NUMERIC(12,2) NOT NULL CHECK (selling_price >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT salesman_monthly_prices_month_is_first_day CHECK (date_trunc('month', month) = month),
  CONSTRAINT salesman_monthly_prices_unique UNIQUE (salesman_id, product_id, unit_type, month)
);

CREATE INDEX salesman_monthly_prices_lookup
  ON public.salesman_monthly_prices (salesman_id, month, product_id, unit_type);

CREATE TRIGGER salesman_monthly_prices_updated_at BEFORE UPDATE ON public.salesman_monthly_prices
FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();

ALTER TABLE public.salesman_monthly_prices ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.salesman_monthly_prices TO authenticated;

-- The Owner sees every salesman's prices; a salesman only their own.
CREATE POLICY salesman_monthly_prices_select ON public.salesman_monthly_prices
  FOR SELECT TO authenticated
  USING (public.current_role() = 'owner' OR salesman_id = auth.uid());

-- Only the salesman sets their own prices; the Owner does not overwrite them.
CREATE POLICY salesman_monthly_prices_write ON public.salesman_monthly_prices
  FOR ALL TO authenticated
  USING (salesman_id = auth.uid() AND public.current_role() = 'salesman')
  WITH CHECK (salesman_id = auth.uid() AND public.current_role() = 'salesman');

CREATE TRIGGER audit_salesman_monthly_prices
AFTER INSERT OR UPDATE OR DELETE ON public.salesman_monthly_prices
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();

-- ============================================================================
-- monthly_targets — the Owner's one target + one bonus % per company, per
-- month. The bonus is earned on the month's whole DP-value once the target
-- is reached.
-- ============================================================================
CREATE TABLE public.monthly_targets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  month DATE NOT NULL,
  target_amount NUMERIC(14,2) NOT NULL CHECK (target_amount >= 0),
  bonus_percent NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (bonus_percent >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT monthly_targets_month_is_first_day CHECK (date_trunc('month', month) = month),
  CONSTRAINT monthly_targets_unique UNIQUE (company_id, month)
);

CREATE TRIGGER monthly_targets_updated_at BEFORE UPDATE ON public.monthly_targets
FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();

ALTER TABLE public.monthly_targets ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.monthly_targets TO authenticated;

CREATE POLICY monthly_targets_select ON public.monthly_targets
  FOR SELECT TO authenticated USING (true);

CREATE POLICY monthly_targets_write ON public.monthly_targets
  FOR ALL TO authenticated
  USING (public.current_role() = 'owner')
  WITH CHECK (public.current_role() = 'owner');

CREATE TRIGGER audit_monthly_targets AFTER INSERT OR UPDATE OR DELETE ON public.monthly_targets
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();

-- ============================================================================
-- delivered_line_profit — one row per delivered line, carrying the figures
-- every profit screen is built from. Only approved deliveries count: a
-- rejected or pending one isn't money earned yet.
--
-- The selling price used is the one the line's own salesman set for the
-- month the delivery falls in. A line with no price entered, or whose unit
-- has no derivable DP, still appears with NULLs so the Owner can see what is
-- missing rather than silently losing the sale from the totals.
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
  smp.selling_price,
  public.product_unit_dp(dsi.product_id, dsi.unit_type) AS dp_price,
  di.delivered_quantity * smp.selling_price          AS revenue,
  di.delivered_quantity * public.product_unit_dp(dsi.product_id, dsi.unit_type) AS dp_value,
  di.delivered_quantity * (smp.selling_price - public.product_unit_dp(dsi.product_id, dsi.unit_type)) AS profit1,
  round(
    di.delivered_quantity * public.product_unit_dp(dsi.product_id, dsi.unit_type)
      * (c.commission_percent / 100.0), 2) AS profit2
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

-- ============================================================================
-- summary_profit — the per-order bottom line the Owner and salesman see once
-- a delivery is approved. The salesman's commission is a cost of that order,
-- so it comes off the profit.
-- ============================================================================
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
  count(*) FILTER (WHERE p.selling_price IS NULL) AS lines_missing_price,
  count(*) FILTER (WHERE p.dp_price IS NULL)      AS lines_missing_dp
FROM public.daily_summaries s
JOIN public.delivered_line_profit p ON p.summary_id = s.id
GROUP BY s.id, s.salesman_id, s.company_id, s.route_id, s.delivery_date, s.commission_amount;

GRANT SELECT ON public.summary_profit TO authenticated;

-- ============================================================================
-- monthly_profit — the month's net profit for a company: every delivered
-- order's profit, plus the target bonus on the month's DP-value once the
-- target is met.
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
  WITH month_start AS (SELECT date_trunc('month', p_month)::date AS m),
  totals AS (
    SELECT
      sp.company_id,
      COALESCE(SUM(sp.revenue), 0)      AS revenue,
      COALESCE(SUM(sp.dp_value), 0)     AS dp_value,
      COALESCE(SUM(sp.profit1), 0)      AS profit1,
      COALESCE(SUM(sp.profit2), 0)      AS profit2,
      COALESCE(SUM(sp.commission_amount), 0) AS commission_total,
      COALESCE(SUM(sp.order_profit), 0) AS orders_profit
    FROM public.summary_profit sp, month_start ms
    WHERE sp.month = ms.m
      AND (p_company_id IS NULL OR sp.company_id = p_company_id)
    GROUP BY sp.company_id
  )
  SELECT
    t.company_id,
    ms.m,
    t.revenue,
    t.dp_value,
    t.profit1,
    t.profit2,
    t.commission_total,
    t.orders_profit,
    mt.target_amount,
    COALESCE(mt.bonus_percent, 0),
    mt.target_amount IS NOT NULL AND t.dp_value >= mt.target_amount AS target_met,
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
  CROSS JOIN month_start ms
  LEFT JOIN public.monthly_targets mt ON mt.company_id = t.company_id AND mt.month = ms.m;
$$;

-- ============================================================================
-- set_monthly_prices — a salesman saves a whole month's price list in one
-- call. Each entry is {product_id, unit_type, selling_price}; a null or
-- negative price clears that entry instead of storing it.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.set_monthly_prices(p_month DATE, p_prices JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_month DATE;
  v_company_id UUID;
  v_entry JSONB;
  v_product_id UUID;
  v_unit public.unit_type;
  v_price NUMERIC;
  v_count INTEGER := 0;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'salesman' OR public.current_status() IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'only an active salesman can set selling prices';
  END IF;
  v_company_id := public.current_company_id();
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'you are not assigned to a company yet — ask the owner to assign one';
  END IF;

  v_month := date_trunc('month', COALESCE(p_month, current_date))::date;

  FOR v_entry IN SELECT * FROM jsonb_array_elements(COALESCE(p_prices, '[]'::jsonb)) LOOP
    v_product_id := (v_entry->>'product_id')::UUID;
    v_unit := (v_entry->>'unit_type')::public.unit_type;
    v_price := NULLIF(v_entry->>'selling_price', '')::NUMERIC;

    IF NOT EXISTS (
      SELECT 1 FROM public.products WHERE id = v_product_id AND company_id = v_company_id
    ) THEN
      RAISE EXCEPTION 'product does not belong to your assigned company';
    END IF;

    IF v_price IS NULL OR v_price <= 0 THEN
      DELETE FROM public.salesman_monthly_prices
        WHERE salesman_id = auth.uid() AND product_id = v_product_id
          AND unit_type = v_unit AND month = v_month;
    ELSE
      INSERT INTO public.salesman_monthly_prices (salesman_id, product_id, unit_type, month, selling_price)
      VALUES (auth.uid(), v_product_id, v_unit, v_month, v_price)
      ON CONFLICT (salesman_id, product_id, unit_type, month)
      DO UPDATE SET selling_price = EXCLUDED.selling_price, updated_at = now();
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

-- ============================================================================
-- copy_prices_from_previous_month — so a salesman starting a new month
-- doesn't retype a 75-product list; they adjust what changed instead.
-- Existing entries for the target month are left alone.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.copy_prices_from_previous_month(p_month DATE)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_month DATE;
  v_count INTEGER;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'salesman' OR public.current_status() IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'only an active salesman can set selling prices';
  END IF;
  v_month := date_trunc('month', COALESCE(p_month, current_date))::date;

  INSERT INTO public.salesman_monthly_prices (salesman_id, product_id, unit_type, month, selling_price)
  SELECT salesman_id, product_id, unit_type, v_month, selling_price
    FROM public.salesman_monthly_prices
    WHERE salesman_id = auth.uid()
      AND month = (v_month - INTERVAL '1 month')::date
  ON CONFLICT (salesman_id, product_id, unit_type, month) DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
