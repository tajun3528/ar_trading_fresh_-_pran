-- ============================================================================
-- Profit is measured against a different figure for each vendor.
--
--   Fresh  — cost is the DP. Extra profit = selling − DP, company cut = 6% of
--            the DP value.
--   Pran   — cost is the After Trade TP. Extra profit = selling − ATP,
--            company cut = 6% of the ATP value.
--
-- The shape is the same, only the basis differs, so it becomes a property of
-- the company rather than two sets of formulas. Everything that reports
-- profit already goes through product_unit_dp(), so teaching that one
-- function about the basis is enough.
--
-- The decomposition holds because ATP is itself about DP + 6%: selling − ATP
-- plus 6% of ATP comes back to the real margin over what the goods cost.
-- ============================================================================
ALTER TABLE public.companies
  ADD COLUMN cost_basis TEXT NOT NULL DEFAULT 'dp'
  CHECK (cost_basis IN ('dp', 'after_trade_tp'));

UPDATE public.companies SET cost_basis = 'after_trade_tp' WHERE name = 'Pran Chocolate';

-- ============================================================================
-- product_unit_dp — what one unit costs, in whichever currency of cost the
-- company reports against.
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
  v_basis TEXT;
  v_per_carton INTEGER;
  v_pcs_per_jar NUMERIC;
  v_pcs_cost NUMERIC;
BEGIN
  SELECT pr.dp_price, pr.per_pcs_dp_price, pr.after_trade_tp_price, pr.per_pcs_tp_price,
         pr.tp_price, pr.factor, pr.pcs_per_carton, pr.poli_per_carton, pr.jar_per_carton,
         pr.box_per_carton, c.cost_basis
    INTO p
    FROM public.products pr
    JOIN public.companies c ON c.id = pr.company_id
   WHERE pr.id = p_product_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  v_basis := p.cost_basis;

  -- ------------------------------------------------------------------ ATP
  IF v_basis = 'after_trade_tp' THEN
    -- A jar/box is quoted directly; pieces come from the per-piece figure;
    -- a carton is however many jars it holds.
    v_pcs_per_jar := CASE
      WHEN p.jar_per_carton IS NOT NULL AND p.jar_per_carton > 0 AND p.factor IS NOT NULL
        THEN p.factor::NUMERIC / p.jar_per_carton
    END;

    -- Scaled from the per-piece figure rather than read off the sheet's jar
    -- column. That column was worked out from Jar/Box Size, which contradicts
    -- the real pack on several products — SmileyEat's ৳661 is 30 pieces when
    -- its jar holds 16, and the Crimson boxes quote a whole carton. The
    -- per-piece figure has no such problem.
    --
    -- Eight products carry no after-trade figures at all; no trade offer
    -- applies to them, so their list TP is what they change hands at.
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

    -- carton
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
-- Nothing may sell below its cost basis, and every priced unit must still
-- have one.
-- ============================================================================
DO $$
DECLARE
  v_problem TEXT;
BEGIN
  SELECT string_agg(format('%s %s (%s)', p.name, pu.unit_type, c.name), ', ') INTO v_problem
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
    JOIN public.companies c ON c.id = p.company_id
   WHERE public.product_unit_dp(pu.product_id, pu.unit_type) IS NULL;
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'these units have no cost: %', v_problem;
  END IF;

  -- Selling a little under the trade price is a real choice — it just makes
  -- the extra profit negative, with the company's 6% still covering it. Only
  -- a gross shortfall means the pack itself is wrong, which is what this
  -- catches: a jar priced as one piece, or a carton priced as a jar.
  SELECT string_agg(format('%s %s sells at %s, costs %s',
                           p.name, pu.unit_type, pu.price,
                           round(public.product_unit_dp(pu.product_id, pu.unit_type), 2)), ', ')
    INTO v_problem
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
   WHERE pu.price < public.product_unit_dp(pu.product_id, pu.unit_type) * 0.8;
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'these units are priced far below cost — the pack is probably wrong: %', v_problem;
  END IF;
END $$;
