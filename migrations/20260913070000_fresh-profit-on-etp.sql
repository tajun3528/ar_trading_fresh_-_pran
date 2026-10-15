-- ============================================================================
-- Fresh profit moves off the DP and onto the ETP:
--
--   extra profit  = selling price − ETP
--   company's 6%  = 6% of the ETP value sold
--
-- The sheet gives ETP per carton and per piece. Every other unit is that
-- per-piece figure times how many pieces it holds, which is how the selling
-- prices are built too — so a box of 24 costs 24 pieces' worth.
--
-- Three products aren't on the sheet (Fresh Chocolate Cookies 200gX8 and the
-- two Choc/Choc Coco Wafer jars). They fall through to the DP as before,
-- rather than losing their cost entirely.
-- ============================================================================
ALTER TABLE public.companies DROP CONSTRAINT IF EXISTS companies_cost_basis_check;
ALTER TABLE public.companies
  ADD CONSTRAINT companies_cost_basis_check
  CHECK (cost_basis IN ('dp', 'after_trade_tp', 'etp'));

UPDATE public.companies SET cost_basis = 'etp' WHERE name = 'Fresh';

CREATE OR REPLACE FUNCTION public.product_unit_dp(p_product_id UUID, p_unit_type public.unit_type)
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
  v_pcs_per_unit NUMERIC;
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
  IF v_basis = 'etp' AND p.etp_per_pcs IS NOT NULL THEN
    IF p_unit_type = 'pcs' THEN
      RETURN p.etp_per_pcs;
    END IF;

    IF p_unit_type = 'carton' THEN
      RETURN COALESCE(p.etp_per_carton, round(p.etp_per_pcs * p.pcs_per_carton, 4));
    END IF;

    -- A jar, box or poli costs what the pieces inside it cost.
    v_per_carton := CASE p_unit_type
      WHEN 'poli' THEN p.poli_per_carton
      WHEN 'jar' THEN p.jar_per_carton
      WHEN 'box' THEN p.box_per_carton
    END;
    IF v_per_carton IS NULL OR v_per_carton <= 0 OR p.pcs_per_carton IS NULL THEN
      -- No piece count for this pack: fall back to splitting the carton.
      IF v_per_carton IS NULL OR v_per_carton <= 0 OR p.etp_per_carton IS NULL THEN
        RETURN NULL;
      END IF;
      RETURN round(p.etp_per_carton / v_per_carton, 4);
    END IF;
    v_pcs_per_unit := p.pcs_per_carton::NUMERIC / v_per_carton;
    RETURN round(p.etp_per_pcs * v_pcs_per_unit, 4);
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

-- ============================================================================
-- Every priced unit must still have a cost, and nothing should be priced far
-- under it — a gross shortfall means a pack count is wrong, not a keen price.
-- ============================================================================
DO $$
DECLARE
  v_problem TEXT;
BEGIN
  SELECT string_agg(format('%s %s', p.name, pu.unit_type), ', ') INTO v_problem
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
   WHERE public.product_unit_dp(pu.product_id, pu.unit_type) IS NULL;
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'these units have no cost: %', v_problem;
  END IF;

  SELECT string_agg(format('%s %s sells at %s, costs %s',
                           p.name, pu.unit_type, pu.price,
                           round(public.product_unit_dp(pu.product_id, pu.unit_type), 2)), ', ')
    INTO v_problem
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
   WHERE pu.price < public.product_unit_dp(pu.product_id, pu.unit_type) * 0.8;
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'these units are priced far below cost — check the pack: %', v_problem;
  END IF;
END $$;
