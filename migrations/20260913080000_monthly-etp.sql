-- ============================================================================
-- The company revises ETP monthly, so the Owner needs to set it per month —
-- and past months have to keep the ETP they were costed at.
--
-- Without that, editing October's ETP would silently rewrite September's
-- profit, because the cost side is computed live rather than stored on the
-- order. (Revenue already survives edits: the line keeps the price it was
-- billed at.)
--
-- A month with no row of its own carries forward the most recent earlier
-- month, so the Owner only records what actually changed. products.etp_* stay
-- as the original sheet values and act as the final fallback.
-- ============================================================================
CREATE TABLE public.product_monthly_etp (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  month DATE NOT NULL,
  etp_per_carton NUMERIC(12,2),
  etp_per_pcs NUMERIC(12,4),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT product_monthly_etp_month_is_first_day CHECK (date_trunc('month', month) = month),
  CONSTRAINT product_monthly_etp_unique UNIQUE (product_id, month)
);

CREATE INDEX product_monthly_etp_lookup ON public.product_monthly_etp (product_id, month DESC);

CREATE TRIGGER product_monthly_etp_updated_at BEFORE UPDATE ON public.product_monthly_etp
FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();

ALTER TABLE public.product_monthly_etp ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.product_monthly_etp TO authenticated;

-- Readable by everyone who can see the catalog; only the Owner sets it.
CREATE POLICY product_monthly_etp_select ON public.product_monthly_etp
  FOR SELECT TO authenticated USING (true);

CREATE POLICY product_monthly_etp_write ON public.product_monthly_etp
  FOR ALL TO authenticated
  USING (public.current_role() = 'owner')
  WITH CHECK (public.current_role() = 'owner');

CREATE TRIGGER audit_product_monthly_etp
AFTER INSERT OR UPDATE OR DELETE ON public.product_monthly_etp
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();

-- The sheet the Owner supplied is September's.
INSERT INTO public.product_monthly_etp (product_id, month, etp_per_carton, etp_per_pcs)
SELECT p.id, DATE '2026-09-01', p.etp_per_carton, p.etp_per_pcs
  FROM public.products p
 WHERE p.etp_per_pcs IS NOT NULL;

-- ============================================================================
-- product_unit_dp_at — the cost of one unit as at a given month. The existing
-- two-argument product_unit_dp stays and delegates here with no month, so
-- every caller and view keeps working while the profit views move over.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.product_unit_dp_at(
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_month DATE
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  p RECORD;
  v_basis TEXT;
  v_per_carton INTEGER;
  v_pcs_per_jar NUMERIC;
  v_pcs_cost NUMERIC;
  v_etp_carton NUMERIC;
  v_etp_pcs NUMERIC;
BEGIN
  SELECT pr.dp_price, pr.per_pcs_dp_price, pr.after_trade_tp_price, pr.per_pcs_tp_price,
         pr.tp_price, pr.factor, pr.pcs_per_carton, pr.poli_per_carton, pr.jar_per_carton,
         pr.box_per_carton, pr.etp_per_carton, pr.etp_per_pcs, c.cost_basis
    INTO p
    FROM public.products pr
    JOIN public.companies c ON c.id = pr.company_id
   WHERE pr.id = p_product_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  v_basis := p.cost_basis;

  -- ------------------------------------------------------------------ ETP
  IF v_basis = 'etp' THEN
    -- That month's ETP, else the last one set before it, else the original.
    SELECT e.etp_per_carton, e.etp_per_pcs INTO v_etp_carton, v_etp_pcs
      FROM public.product_monthly_etp e
     WHERE e.product_id = p_product_id
       AND (p_month IS NULL OR e.month <= date_trunc('month', p_month)::date)
     ORDER BY e.month DESC
     LIMIT 1;

    v_etp_carton := COALESCE(v_etp_carton, p.etp_per_carton);
    v_etp_pcs := COALESCE(v_etp_pcs, p.etp_per_pcs);

    IF v_etp_pcs IS NOT NULL OR v_etp_carton IS NOT NULL THEN
      IF p_unit_type = 'pcs' THEN
        IF v_etp_pcs IS NOT NULL THEN
          RETURN v_etp_pcs;
        END IF;
        IF p.pcs_per_carton > 0 THEN
          RETURN round(v_etp_carton / p.pcs_per_carton, 4);
        END IF;
        RETURN NULL;
      END IF;

      IF p_unit_type = 'carton' THEN
        IF v_etp_carton IS NOT NULL THEN
          RETURN v_etp_carton;
        END IF;
        IF p.pcs_per_carton > 0 THEN
          RETURN round(v_etp_pcs * p.pcs_per_carton, 4);
        END IF;
        RETURN NULL;
      END IF;

      v_per_carton := CASE p_unit_type
        WHEN 'poli' THEN p.poli_per_carton
        WHEN 'jar' THEN p.jar_per_carton
        WHEN 'box' THEN p.box_per_carton
      END;
      IF v_per_carton IS NULL OR v_per_carton <= 0 THEN
        RETURN NULL;
      END IF;
      IF v_etp_pcs IS NOT NULL AND p.pcs_per_carton IS NOT NULL AND p.pcs_per_carton > 0 THEN
        RETURN round(v_etp_pcs * (p.pcs_per_carton::NUMERIC / v_per_carton), 4);
      END IF;
      IF v_etp_carton IS NOT NULL THEN
        RETURN round(v_etp_carton / v_per_carton, 4);
      END IF;
      RETURN NULL;
    END IF;
  END IF;

  -- ------------------------------------------------------------------ ATP
  IF v_basis = 'after_trade_tp' THEN
    v_pcs_per_jar := CASE
      WHEN p.jar_per_carton IS NOT NULL AND p.jar_per_carton > 0 AND p.factor IS NOT NULL
        THEN p.factor::NUMERIC / p.jar_per_carton
    END;
    v_pcs_cost := COALESCE(p.per_pcs_tp_price, p.tp_price);
    IF v_pcs_cost IS NULL THEN
      RETURN NULL;
    END IF;

    IF p_unit_type = 'pcs' THEN
      RETURN v_pcs_cost;
    END IF;
    IF p_unit_type IN ('jar', 'box', 'poli') THEN
      IF v_pcs_per_jar IS NULL OR v_pcs_per_jar <= 0 THEN
        RETURN NULL;
      END IF;
      RETURN round(v_pcs_cost * v_pcs_per_jar, 4);
    END IF;
    IF p.factor IS NULL OR p.factor <= 0 THEN
      RETURN NULL;
    END IF;
    RETURN round(v_pcs_cost * p.factor, 4);
  END IF;

  -- ------------------------------------------------------------------- DP
  IF p.dp_price IS NULL THEN
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

CREATE OR REPLACE FUNCTION public.product_unit_dp(p_product_id UUID, p_unit_type public.unit_type)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$ SELECT public.product_unit_dp_at(p_product_id, p_unit_type, current_date); $$;

-- ============================================================================
-- Delivered lines cost against the ETP of the month they were delivered in,
-- so a later revision can't reach back and change a closed month.
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
  public.product_unit_dp_at(dsi.product_id, dsi.unit_type, s.delivery_date) AS dp_price,
  di.delivered_quantity * dsi.unit_price             AS revenue,
  di.delivered_quantity * public.product_unit_dp_at(dsi.product_id, dsi.unit_type, s.delivery_date) AS dp_value,
  di.delivered_quantity * (dsi.unit_price - public.product_unit_dp_at(dsi.product_id, dsi.unit_type, s.delivery_date)) AS profit1,
  round(
    di.delivered_quantity * public.product_unit_dp_at(dsi.product_id, dsi.unit_type, s.delivery_date)
      * (c.commission_percent / 100.0), 2) AS profit2,
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

-- ============================================================================
-- set_monthly_etp — the Owner records a month's ETP for a set of products.
-- A null figure clears that product's row for the month, so it falls back to
-- the previous month again.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.set_monthly_etp(p_month DATE, p_rows JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_month DATE;
  v_row JSONB;
  v_product_id UUID;
  v_carton NUMERIC;
  v_pcs NUMERIC;
  v_count INTEGER := 0;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'only the owner can set ETP';
  END IF;
  v_month := date_trunc('month', COALESCE(p_month, current_date))::date;

  FOR v_row IN SELECT * FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb)) LOOP
    v_product_id := (v_row->>'product_id')::UUID;
    v_carton := NULLIF(v_row->>'etp_per_carton', '')::NUMERIC;
    v_pcs := NULLIF(v_row->>'etp_per_pcs', '')::NUMERIC;

    IF (v_carton IS NULL OR v_carton <= 0) AND (v_pcs IS NULL OR v_pcs <= 0) THEN
      DELETE FROM public.product_monthly_etp
       WHERE product_id = v_product_id AND month = v_month;
      CONTINUE;
    END IF;

    INSERT INTO public.product_monthly_etp (product_id, month, etp_per_carton, etp_per_pcs)
    VALUES (v_product_id, v_month, v_carton, v_pcs)
    ON CONFLICT (product_id, month) DO UPDATE
      SET etp_per_carton = EXCLUDED.etp_per_carton,
          etp_per_pcs = EXCLUDED.etp_per_pcs,
          updated_at = now();
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;
GRANT EXECUTE ON FUNCTION public.set_monthly_etp(DATE, JSONB) TO authenticated;
