-- ============================================================================
-- Pran Chocolate: the Owner's counted stock, and the real jar/box selling
-- prices.
--
-- The prices double as a check on the pack nesting, since jar price divided
-- by piece price is the pieces in a jar. Seventeen of the twenty confirmed
-- what was already stored. Three did not:
--
--   Choco Choco Cookies & Cream  ৳270 / ৳3.37 = 80 pcs a container, so 1440 /
--     80 = 18 containers to a carton, not the 6 read off the sheet. The name
--     said "80pcs container" all along.
--   Crimson Eclair Octagonal     ৳140 / ৳136.98 = 1 — the box IS the piece,
--     so 12 boxes to a carton, not 1.
--   Premio Choco Card            ৳80 / ৳80 = 1, same again: 12 to a carton,
--     and it had no jar level at all before.
--
-- The other two Crimson boxes follow the Octagonal's pattern — they are the
-- same kind of single-piece box — so their nesting is corrected to match even
-- though the Owner gave no price for them.
-- ============================================================================
CREATE TEMP TABLE _pran_fix (
  item_code TEXT PRIMARY KEY,
  jars_per_carton INTEGER,
  jar_price NUMERIC(12,2),
  carton_stock INTEGER,
  jar_stock INTEGER
) ON COMMIT DROP;

-- jars_per_carton is only given where it needs correcting; NULL leaves it.
INSERT INTO _pran_fix (item_code, jars_per_carton, jar_price, carton_stock, jar_stock) VALUES
  ('34242', NULL, 220, 2,  8),   -- M&S 20pcs tray
  ('45228', NULL,  95, 3,  9),   -- M&S Chain-N
  ('52199', NULL, 250, 1,  2),   -- PRAN Eclair Strawberry
  ('52238', NULL, 380, 1,  2),   -- Pran Lollipop Sports Series
  ('52283', NULL, 300, 2, 11),   -- Fruitfil Litchi 200 pcs
  ('52349', NULL, 240, 3,  9),   -- Fruto Candy Milk
  ('52675', NULL, 350, 6,  6),   -- SmileyEat
  ('52714', NULL, 200, 0, 10),   -- PRAN Chew Candy Assorted
  ('52989', NULL, 105, 0,  8),   -- SIPCO ORANGO Tasty Saline
  ('53123', NULL,  80, 4,  5),   -- Hurray My Love Wafer
  ('53285', NULL, 290, 0, 14),   -- PRAN Jelly Candy
  ('53705', NULL, 345, 3,  0),   -- Hurray Choco Egg
  ('72022', NULL, 355, 3,  4),   -- Treat Cone Wafer
  ('72985', 12,   140, 1, 10),   -- Crimson Eclair Octagonal — box is the piece
  ('74059', 18,   270, 1,  1),   -- Choco Choco Cookies — 80 pcs a container
  ('74091', NULL, 140, 6,  0),   -- Hurray Chocolate Coated Wafer
  ('74093', NULL, 165, 2,  6),   -- Chao Chao Mini Assorted Lollipop
  ('74349', 12,    80, 4,  2),   -- Premio Choco Card — had no jar level
  ('74460', NULL, 160, 6,  5),   -- PRAN Jelly Bear Cup
  ('74496', NULL, 195, 3,  9);   -- Bro Crispy Peanut Bar

-- Nesting-only corrections, no price or stock given.
INSERT INTO _pran_fix (item_code, jars_per_carton) VALUES
  ('72983', 30),   -- Crimson Eclair Double Love-105g — 30 single boxes a carton
  ('72984', 24);   -- Crimson Eclair Round Box-135g   — 24 single boxes a carton

DO $$
DECLARE
  v_problem TEXT;
BEGIN
  SELECT string_agg(k.item_code, ', ') INTO v_problem
    FROM _pran_fix k
   WHERE NOT EXISTS (
     SELECT 1 FROM public.products p JOIN public.companies c ON c.id = p.company_id
      WHERE c.name = 'Pran Chocolate' AND p.item_code = k.item_code);
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'these item codes are not Pran products: %', v_problem;
  END IF;

  SELECT string_agg(format('%s (factor %s / %s jars)', p.name, p.factor, k.jars_per_carton), ', ')
    INTO v_problem
    FROM _pran_fix k
    JOIN public.products p ON p.item_code = k.item_code
   WHERE k.jars_per_carton IS NOT NULL AND p.factor % k.jars_per_carton <> 0;
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'pieces per carton does not divide evenly by jars: %', v_problem;
  END IF;
END $$;

-- ============================================================================
-- Corrected nesting
-- ============================================================================
UPDATE public.products p
   SET jar_per_carton = k.jars_per_carton
  FROM _pran_fix k
 WHERE p.item_code = k.item_code AND k.jars_per_carton IS NOT NULL;

-- ============================================================================
-- Jar/box price as given, and the carton follows from it so the two can't
-- drift apart. Products whose nesting changed but carry no given price get
-- their jar rebuilt from the piece price on the corrected count.
-- ============================================================================
INSERT INTO public.product_units (product_id, unit_type, price)
SELECT p.id, 'jar',
       COALESCE(k.jar_price,
                ROUND(COALESCE(p.per_pcs_tp_price, p.tp_price) * (p.factor::NUMERIC / p.jar_per_carton), 2))
  FROM _pran_fix k
  JOIN public.products p ON p.item_code = k.item_code
 WHERE p.jar_per_carton IS NOT NULL
ON CONFLICT (product_id, unit_type) DO UPDATE
  SET price = EXCLUDED.price, updated_at = now();

UPDATE public.product_units pu
   SET price = ROUND(jar.price * p.jar_per_carton, 2), updated_at = now()
  FROM _pran_fix k, public.products p, public.product_units jar
 WHERE p.item_code = k.item_code
   AND pu.product_id = p.id AND pu.unit_type = 'carton'
   AND jar.product_id = p.id AND jar.unit_type = 'jar'
   AND p.jar_per_carton IS NOT NULL;

-- ============================================================================
-- Counted stock. Set outright rather than added to — this is the Owner's
-- count of what is on the shelf, not a delivery arriving.
-- ============================================================================
INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
SELECT p.id, 'carton', k.carton_stock, 0
  FROM _pran_fix k
  JOIN public.products p ON p.item_code = k.item_code
 WHERE k.carton_stock IS NOT NULL
ON CONFLICT (product_id, unit_type) DO UPDATE
  SET available_qty = EXCLUDED.available_qty, updated_at = now();

INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
SELECT p.id, 'jar', k.jar_stock, 0
  FROM _pran_fix k
  JOIN public.products p ON p.item_code = k.item_code
 WHERE k.jar_stock IS NOT NULL AND p.jar_per_carton IS NOT NULL
ON CONFLICT (product_id, unit_type) DO UPDATE
  SET available_qty = EXCLUDED.available_qty, updated_at = now();

-- ============================================================================
-- Every priced unit must still cost something, and no unit may sell below it.
-- ============================================================================
DO $$
DECLARE
  v_problem TEXT;
BEGIN
  SELECT string_agg(format('%s (%s)', p.name, pu.unit_type), ', ') INTO v_problem
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
    JOIN public.companies c ON c.id = p.company_id
   WHERE c.name = 'Pran Chocolate'
     AND public.product_unit_dp(pu.product_id, pu.unit_type) IS NULL;
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'these Pran units have no DP cost: %', v_problem;
  END IF;

  SELECT string_agg(format('%s %s sells at %s but costs %s',
                           p.name, pu.unit_type, pu.price,
                           round(public.product_unit_dp(pu.product_id, pu.unit_type), 2)), ', ')
    INTO v_problem
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
    JOIN public.companies c ON c.id = p.company_id
   WHERE c.name = 'Pran Chocolate'
     AND pu.price < public.product_unit_dp(pu.product_id, pu.unit_type);
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'these Pran units would sell at a loss: %', v_problem;
  END IF;
END $$;
