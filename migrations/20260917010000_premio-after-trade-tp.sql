-- ============================================================================
-- Premio Choco Bueno had no cost price at all, so every unit's cost came back
-- null and it sold showing no margin figure.
--
-- The owner sells this one at the After Trade TP: there is no mark-up, and the
-- earning is the company's 6% on the ATP value. Recording ATP equal to the
-- selling price is what makes that come out right — extra profit lands on
-- zero rather than on "unknown", and the 6% is taken from a real figure.
--
-- The figures are derived from the carton price actually on the product
-- rather than typed in here, so this cannot go stale if the price is revised
-- between writing and running it. product_unit_dp_at then rebuilds the rest:
--   piece  = per_pcs_tp_price
--   jar    = per_pcs_tp_price * factor / jars per carton
--   carton = per_pcs_tp_price * factor
-- ============================================================================
DO $$
DECLARE
  v_id UUID;
  v_carton NUMERIC;
  v_factor INTEGER;
  v_jars INTEGER;
  v_sell NUMERIC;
  v_cost NUMERIC;
  v_unit public.unit_type;
BEGIN
  SELECT p.id, p.factor, p.jar_per_carton INTO v_id, v_factor, v_jars
    FROM public.products p WHERE p.name ILIKE 'Premio Choco Bueno 20g%';
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Premio Choco Bueno not found';
  END IF;
  IF v_factor IS NULL OR v_factor <= 0 OR v_jars IS NULL OR v_jars <= 0 THEN
    RAISE EXCEPTION 'packaging is incomplete: factor=%, jars per carton=%', v_factor, v_jars;
  END IF;

  SELECT price INTO v_carton FROM public.product_units
   WHERE product_id = v_id AND unit_type = 'carton';
  IF v_carton IS NULL THEN
    RAISE EXCEPTION 'no carton price to derive the After Trade TP from';
  END IF;

  UPDATE public.products
     SET per_pcs_tp_price     = round(v_carton / v_factor, 4),
         after_trade_tp_price = round(v_carton / v_jars, 2)
   WHERE id = v_id;

  -- Every tier must now cost exactly what it sells for. Anything else means
  -- the packaging counts and the prices disagree, and the 6% would be taken
  -- from the wrong number.
  FOR v_unit, v_sell IN
    SELECT pu.unit_type, pu.price FROM public.product_units pu WHERE pu.product_id = v_id
  LOOP
    v_cost := public.product_unit_dp(v_id, v_unit);
    IF v_cost IS NULL THEN
      RAISE EXCEPTION 'the % still has no cost', v_unit;
    END IF;
    IF round(v_sell, 2) <> round(v_cost, 2) THEN
      RAISE EXCEPTION '% sells at % but its After Trade TP works out to %', v_unit, v_sell, v_cost;
    END IF;
  END LOOP;
END $$;
