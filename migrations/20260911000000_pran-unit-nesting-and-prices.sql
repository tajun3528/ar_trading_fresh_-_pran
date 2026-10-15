-- ============================================================================
-- Pran Chocolate: pack nesting and per-unit prices.
--
-- Two things were wrong. Every carton was priced at the sheet's TP, but for
-- Pran that column is a PER PIECE price — so a carton of M&S Small tube, 192
-- pieces, was priced at ৳8. And the products had no jar or piece unit at all,
-- only a carton, so nothing smaller could be ordered.
--
-- The sheet's "JAR/Box in a carton" column gives the nesting, and Factor is
-- the total pieces in a carton, so pieces per jar falls out as Factor / jars.
-- Prices are built from the after-trade figures, per the Owner:
--
--   piece  = Per pcs TP
--   jar    = After Trade TP        (the sheet's own jar price)
--   carton = jar x jars per carton
--
-- Eight products have no after-trade figures on the sheet; those fall back to
-- the list per-piece TP, with the carton as piece x Factor.
--
-- dp_price is also corrected from a per-piece figure to the carton cost,
-- which is what it means everywhere else and what the profit calculation
-- divides down from.
-- ============================================================================
-- The sheet's After Trade TP is the jar price, but only where it was worked
-- out from the real pack. Where its implied pieces-per-jar disagrees with
-- Factor / jars, the piece price is the reliable figure and the jar is built
-- from that instead.
CREATE OR REPLACE FUNCTION public._pran_jar_price(p public.products, p_jars INTEGER)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p.after_trade_tp_price IS NOT NULL
     AND p.per_pcs_tp_price > 0
     AND abs((p.after_trade_tp_price / p.per_pcs_tp_price) - (p.factor::NUMERIC / p_jars))
         <= GREATEST(1, (p.factor::NUMERIC / p_jars) * 0.02)
      THEN p.after_trade_tp_price
    ELSE COALESCE(p.per_pcs_tp_price, p.tp_price) * (p.factor::NUMERIC / p_jars)
  END;
$$;

CREATE TEMP TABLE _pran_packs (item_code TEXT PRIMARY KEY, jars_per_carton INTEGER) ON COMMIT DROP;

INSERT INTO _pran_packs (item_code, jars_per_carton) VALUES
  ('31632', 9),    -- Treat Dairy Milk-12.5gm            216 / 9  = 24
  ('34227', 32),   -- Fruitfil Litchi 75 pcs            2400 / 32 = 75
  ('34241', 6),    -- M&S Small tube-32pcs               192 / 6  = 32
  ('34242', 12),   -- M&S 20pcs tray                     240 / 12 = 20
  ('34248', NULL), -- PRAN Glucose D 400g box            no jar level, 12 pcs a carton
  ('34773', 6),    -- PRAN Lollipop Orange 100 Pcs       600 / 6  = 100
  ('45228', 12),   -- M&S Chain-N                        288 / 12 = 24
  ('47312', 4),    -- Buddy wafer Milk Mega 20 pcs Jar    80 / 4  = 20
  ('47341', 15),   -- Buddy wafer Chocolate mini 25 Pcs  375 / 15 = 25
  ('48414', 6),    -- Treat Coffee Chocolate Bar 20gm    240 / 6  = 40
  ('50698', NULL), -- M&S Baby feeder Small              no pack data on the sheet
  ('52199', 12),   -- PRAN Eclair Strawberry 300pcs     3600 / 12 = 300
  ('52238', 6),    -- Pran Lollipop Sports Series        600 / 6  = 100
  ('52283', 15),   -- Fruitfil Litchi 200 pcs X 15Jar   3000 / 15 = 200
  ('52293', 12),   -- PRAN Pulse Candy Mango            2400 / 12 = 200
  ('52349', 15),   -- Fruto Candy Milk 300pcs jar       4500 / 15 = 300
  ('52675', 8),    -- SmileyEat 16pcs X 8jar             128 / 8  = 16
  ('52714', 12),   -- PRAN Chew Candy Assorted          1800 / 12 = 150
  ('52989', 12),   -- SIPCO ORANGO Tasty Saline          240 / 12 = 20
  ('53123', 12),   -- Hurray My Love Wafer 10 Pcs        120 / 12 = 10
  ('53285', 15),   -- PRAN Jelly Candy 200pcs X 15Jar   3000 / 15 = 200
  ('53705', 6),    -- Hurray Choco Egg 45pcs jar         270 / 6  = 45
  ('72022', 6),    -- Treat Cone Wafer 25 Pcs X 6 Jar    150 / 6  = 25
  ('72044', 2),    -- Hurray Pillow Wafer 24Pcs X 2 Pouch 48 / 2  = 24
  ('72059', NULL), -- Divino Chocolate Bar 150gm         no pack data on the sheet
  ('72354', NULL), -- KENSINGTON CREAMY WAFER BIS        no jar level, 12 pcs a carton
  ('72480', 6),    -- Eyedrop Ball Candy 50pcs x 6 Jar   300 / 6  = 50
  ('72921', 12),   -- Whirly Lollipop Love Shape         360 / 12 = 30
  ('72923', 12),   -- Starlight Candy Cane 50pcs         600 / 12 = 50
  ('72983', 1),    -- Crimson Eclair Double Love-105g     30 / 1  = 30
  ('72984', 1),    -- Crimson Eclair Round Box-135g       24 / 1  = 24
  ('72985', 1),    -- Crimson Eclair Octagonal Box-135g   12 / 1  = 12
  ('74010', 30),   -- Treat Coco Choco Coconut Bar       240 / 30 = 8
  ('74059', 6),    -- PRAN Choco Choco Cookies & Cream  1440 / 6  = 240
  ('74091', 6),    -- Hurray Chocolate Coated Wafer      210 / 6  = 35
  ('74093', 12),   -- Chao Chao Mini Assorted Lollipop   864 / 12 = 72
  ('74349', NULL), -- Premio Choco Card                  no pack data on the sheet
  ('74460', 6),    -- PRAN Jelly Bear Cup 20pcs X 6jar   120 / 6  = 20
  ('74467', 6),    -- Pran Lolipop Love Series           600 / 6  = 100
  ('74468', 8),    -- Pran Biggy Assorted Lollipop Twist 240 / 8  = 30
  ('74496', 12),   -- Bro Crispy Peanut Bar 50 Pcs       600 / 12 = 50
  ('74498', 15),   -- Treat Chocolate 30 pcs Jar         450 / 15 = 30
  ('74506', 8);    -- Chao Chao Lollipop Bucket 100 Pcs  800 / 8  = 100

-- ============================================================================
-- Guards. These figures were read off a price sheet, so anything that doesn't
-- reconcile should stop the migration rather than quietly reprice a product.
-- ============================================================================
DO $$
DECLARE
  v_problem TEXT;
BEGIN
  -- Every code must match a Pran product, and every Pran product be covered.
  SELECT string_agg(k.item_code, ', ') INTO v_problem
    FROM _pran_packs k
   WHERE NOT EXISTS (
     SELECT 1 FROM public.products p JOIN public.companies c ON c.id = p.company_id
      WHERE c.name = 'Pran Chocolate' AND p.item_code = k.item_code);
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'these item codes are not Pran products: %', v_problem;
  END IF;

  SELECT string_agg(p.item_code, ', ') INTO v_problem
    FROM public.products p JOIN public.companies c ON c.id = p.company_id
   WHERE c.name = 'Pran Chocolate'
     AND NOT EXISTS (SELECT 1 FROM _pran_packs k WHERE k.item_code = p.item_code);
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'these Pran products have no pack entry: %', v_problem;
  END IF;

  -- A carton must divide evenly into jars.
  SELECT string_agg(format('%s (factor %s / %s jars)', p.name, p.factor, k.jars_per_carton), ', ')
    INTO v_problem
    FROM _pran_packs k
    JOIN public.products p ON p.item_code = k.item_code
   WHERE k.jars_per_carton IS NOT NULL
     AND (p.factor IS NULL OR p.factor % k.jars_per_carton <> 0);
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'pieces per carton does not divide evenly by jars: %', v_problem;
  END IF;

  -- Note: the sheet's After Trade price is not always usable as the jar
  -- price. For Bro Crispy, Pran Biggy and SmileyEat it was worked out from
  -- the Jar/Box Size column, which disagrees with both the product name and
  -- Factor (e.g. Bro Crispy is "50 Pcs x 12 Jar" and Factor 600 = 50 x 12,
  -- but Jar/Box Size says 30 and the jar price is 30 x the piece price).
  -- Rather than fail on those, the price build below uses the sheet's jar
  -- figure only where it reconciles with the pack, and derives it otherwise.
END $$;

-- ============================================================================
-- Nesting
-- ============================================================================
UPDATE public.products p
   SET pcs_per_carton = p.factor,
       jar_per_carton = k.jars_per_carton
  FROM _pran_packs k
 WHERE p.item_code = k.item_code;

-- ============================================================================
-- dp_price becomes the carton cost — everywhere else in the app that column
-- means "what a carton costs", and product_unit_dp() divides it down.
-- ============================================================================
-- Built from the per-piece cost times the carton's pieces, which sidesteps
-- the same Jar/Box Size contradiction on the After Trade DP column.
UPDATE public.products p
   SET dp_price = ROUND(COALESCE(p.per_pcs_dp_price, p.dp_price) * p.factor, 2)
  FROM _pran_packs k
 WHERE p.item_code = k.item_code;

-- ============================================================================
-- Sellable units. Rebuilt from scratch: the existing carton rows hold a
-- per-piece price and no Pran order has ever been placed, so there is no
-- history to preserve here (a placed order copies its own unit_price anyway).
-- ============================================================================
DELETE FROM public.product_units pu
 USING public.products p, public.companies c
 WHERE pu.product_id = p.id AND p.company_id = c.id AND c.name = 'Pran Chocolate';

-- Piece
INSERT INTO public.product_units (product_id, unit_type, price)
SELECT p.id, 'pcs', ROUND(COALESCE(p.per_pcs_tp_price, p.tp_price), 2)
  FROM _pran_packs k
  JOIN public.products p ON p.item_code = k.item_code
 WHERE COALESCE(p.per_pcs_tp_price, p.tp_price) > 0;

-- Jar / box, where the pack has one. The sheet's own jar price is kept when
-- it matches the pack; where it was worked out from a contradictory Jar/Box
-- Size it is recomputed from the piece price instead.
INSERT INTO public.product_units (product_id, unit_type, price)
SELECT p.id, 'jar', ROUND(public._pran_jar_price(p, k.jars_per_carton), 2)
  FROM _pran_packs k
  JOIN public.products p ON p.item_code = k.item_code
 WHERE k.jars_per_carton IS NOT NULL
   AND COALESCE(p.after_trade_tp_price, p.per_pcs_tp_price, p.tp_price) > 0;

-- Carton
INSERT INTO public.product_units (product_id, unit_type, price)
SELECT p.id, 'carton',
       ROUND(
         CASE
           WHEN k.jars_per_carton IS NOT NULL
             THEN public._pran_jar_price(p, k.jars_per_carton) * k.jars_per_carton
           ELSE COALESCE(p.per_pcs_tp_price, p.tp_price) * p.factor
         END, 2)
  FROM _pran_packs k
  JOIN public.products p ON p.item_code = k.item_code
 WHERE COALESCE(p.per_pcs_tp_price, p.tp_price) > 0;

-- ============================================================================
-- Every priced unit must now cost something, or profit silently reads zero.
-- ============================================================================
DO $$
DECLARE
  v_missing TEXT;
BEGIN
  SELECT string_agg(format('%s (%s)', p.name, pu.unit_type), ', ') INTO v_missing
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
    JOIN public.companies c ON c.id = p.company_id
   WHERE c.name = 'Pran Chocolate'
     AND public.product_unit_dp(pu.product_id, pu.unit_type) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'these Pran units have no DP cost: %', v_missing;
  END IF;
END $$;
