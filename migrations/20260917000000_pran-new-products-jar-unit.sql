-- ============================================================================
-- Two new Pran products could only be ordered by the carton.
--
-- The order form offers a unit only when that unit has a price row in
-- product_units, and both products had been given a carton price and nothing
-- else. Their jar_per_carton was also empty, so even with a price the app had
-- no way to know a carton holds 15 (or 6) jars — the nested-packaging rule is
-- what lets a carton in the warehouse count toward jar availability.
--
--   Divino Chocolate   30 pcs × 15 jar  = 450 pcs per carton
--   Premio Choco Bueno 20g × 40 pcs × 6 = 240 pcs per carton
--
-- "Basket" on the Premio sheet is the same tier as a jar everywhere else in
-- the Pran catalog, so it is recorded as a jar rather than inventing a unit
-- that no report, stock page or delivery round would understand.
-- ============================================================================
DO $$
DECLARE
  v_divino UUID;
  v_premio UUID;
  v_carton NUMERIC;
BEGIN
  SELECT id INTO v_divino FROM public.products WHERE name ILIKE 'Divino Chocolate 30pcs%';
  SELECT id INTO v_premio FROM public.products WHERE name ILIKE 'Premio Choco Bueno 20g%';
  IF v_divino IS NULL OR v_premio IS NULL THEN
    RAISE EXCEPTION 'expected both new Pran products to exist (divino=%, premio=%)', v_divino, v_premio;
  END IF;

  -- ------------------------------------------------------------- packaging
  -- factor is pcs per carton for a Pran product: product_unit_dp_at derives
  -- the per-jar cost as per_pcs_tp_price * (factor / jar_per_carton), so a
  -- null factor left the cost of every unit null.
  UPDATE public.products
     SET factor = 450, pcs_per_carton = 450, jar_per_carton = 15, jar_box_size = 30
   WHERE id = v_divino;

  UPDATE public.products
     SET factor = 240, pcs_per_carton = 240, jar_per_carton = 6, jar_box_size = 40
   WHERE id = v_premio;

  -- ---------------------------------------------------------- Divino units
  SELECT price INTO v_carton FROM public.product_units
   WHERE product_id = v_divino AND unit_type = 'carton';
  IF v_carton IS NULL THEN
    RAISE EXCEPTION 'Divino has no carton price to derive its jar and piece prices from';
  END IF;

  -- Derived from the carton price so the tiers cannot contradict each other.
  INSERT INTO public.product_units (product_id, unit_type, price)
  VALUES (v_divino, 'jar', round(v_carton / 15, 2)),
         (v_divino, 'pcs', round(v_carton / 450, 2))
  ON CONFLICT (product_id, unit_type) DO UPDATE SET price = EXCLUDED.price;

  -- ---------------------------------------------------------- Premio units
  SELECT price INTO v_carton FROM public.product_units
   WHERE product_id = v_premio AND unit_type = 'carton';
  IF v_carton IS NULL THEN
    RAISE EXCEPTION 'Premio has no carton price to derive its jar and piece prices from';
  END IF;

  INSERT INTO public.product_units (product_id, unit_type, price)
  VALUES (v_premio, 'jar', round(v_carton / 6, 2)),
         (v_premio, 'pcs', round(v_carton / 240, 2))
  ON CONFLICT (product_id, unit_type) DO UPDATE SET price = EXCLUDED.price;

  -- ------------------------------------------------------ never sell under
  -- Divino has its After Trade TP, so the derived prices can be checked.
  -- Premio's cost fields are still empty and are the owner's to supply, so
  -- there is nothing to check it against yet.
  IF public.product_unit_dp(v_divino, 'jar') IS NOT NULL
     AND (SELECT price FROM public.product_units WHERE product_id = v_divino AND unit_type = 'jar')
         < public.product_unit_dp(v_divino, 'jar') THEN
    RAISE EXCEPTION 'Divino jar price would sell below its After Trade TP';
  END IF;
END $$;
