-- ============================================================================
-- Fresh gets an ETP (effective trade price) per carton and per piece, and
-- profit moves onto it:
--
--   extra profit  = selling price − ETP
--   company's 6%  = 6% of the ETP value sold
--
-- That is the same shape Pran already uses against its After Trade TP, so it
-- becomes another cost_basis rather than a second set of formulas.
--
-- Names on the price sheet don't always match the catalog exactly — "12G"
-- against "12g", a missing "Fresh" prefix, a stray space — so matching is on
-- the name with case and punctuation stripped, and anything that fails to
-- match stops the migration rather than being skipped.
-- ============================================================================
ALTER TABLE public.products ADD COLUMN etp_per_carton NUMERIC(12,2);
ALTER TABLE public.products ADD COLUMN etp_per_pcs NUMERIC(12,4);

CREATE TEMP TABLE _fresh_etp (name TEXT, etp_ctn NUMERIC(12,2), etp_pcs NUMERIC(12,4)) ON COMMIT DROP;

INSERT INTO _fresh_etp (name, etp_ctn, etp_pcs) VALUES
  ('Fresh F.Sndwch Crm Pineapple-48X17G',      192.00,   4.00),
  ('Fresh F.Sndwch Crm Choc Bist-48X17G',      204.00,   4.25),
  ('Fresh Potatoz Spicy Biscuit-13GX72',            272.84,   3.79),
  ('Fresh Sugar Crush Biscuit 17GX48',              192.00,   4.00),
  ('Fresh Lexus Vegetables Crackers 48x15g',        180.71,   3.76),
  ('Fresh Energy Power Biscuit 16gx48',             184.32,   3.84),
  ('Fresh Fun.Fill Milk Crm Biscuits-48X17G',       192.00,   4.00),
  ('Fresh Orangy Biscuit-24X38G',                   187.20,   7.80),
  ('Fresh Energy Power Biscuit 40gX24',             192.00,   8.00),
  ('Fresh Sweet n Salty Biscuit 37gx24',            195.00,   8.13),
  ('Fresh Sugar Crush Biscuit 34gx24',              183.53,   7.65),
  ('Fresh Milk Shakti Biscuit 40gx24',              192.00,   8.00),
  ('Fresh F.Sndwch Crm Choc Bist-24X34G',      195.84,   8.16),
  ('Fresh F.Fill Sndwch Crm Pineapple-24X35G',      192.00,   8.00),
  ('Fresh Fun.Fill Milk Crm Biscuits-24X35G',       192.00,   8.00),
  ('Fresh Dry Cake 24X24G',                         368.64,   7.68),
  ('Fresh Coconut Cookies-24X72G',                  368.64,  15.36),
  ('Fresh Super Delicious Biscuit-24X72G',          384.00,  16.00),
  ('Fresh Potatoz Spicy Biscuit-50GX24',            384.00,  16.00),
  ('Fresh Twisty Vanilla Cream Biscui-24X50G',      384.00,  16.00),
  ('Fresh Chocolate Chip Cookies 60GX24',           384.00,  16.00),
  ('Fresh Choco Love Biscuit-45GX24',               384.00,  16.00),
  ('Fresh Healthy Choice Salted 80gX24PC',          384.00,  16.00),
  ('Fresh Lexus Vegetables Crackers 63gx24PC',      384.00,  16.00),
  ('Fresh Orangy Biscuits-8X139G',                  252.24,  31.53),
  ('Fresh Tea Partner Cookies Biscuit-6X185G',      252.00,  42.00),
  ('Fresh Energy Power Biscuit 180gx6',             232.62,  38.77),
  ('Fresh Salted Cookies-160GX6',                   252.00,  42.00),
  ('Fresh Milk Marie Biscuit 200gX6',               252.00,  42.00),
  ('Fresh Butter Cookies Family -170GX8',           316.24,  39.53),
  ('Fresh Coconut Cookies-185GX8',                  316.23,  39.53),
  ('Fresh Coconut Cookies-240GX8',                  390.00,  48.75),
  ('Fresh Super Delicious Cookies 160GX8',          336.00,  42.00),
  ('Fresh Chocolate Chip Cookies 200gX8',           421.65,  52.71),
  ('Potatoz Spicy Biscuit-192g-10P',                800.00,  80.00),
  ('Fresh Lexus Vegetable Crackers 10x180g',        600.00,  60.00),
  ('Fresh Fantasy Choc Filled Cookis-175GX12',     1382.40, 115.20),
  ('Fresh Fantasy Choc Filled Cookies-75GX24',     1218.46,  50.77),
  ('Fresh Butter Cookies Jar-8X500G',               960.00, 120.00),
  ('Fresh Butter Cookies Jar-750GX6',               960.00, 160.00),
  ('Fresh Fantasy Choc Filled Cookies-Jar 400GX6', 1536.00, 256.00),
  ('Fresh Special Toast Biscuits',                  252.00,  42.00),
  ('Fresh Sweet Toast Biscuits',                    330.00,  55.00),
  ('Fresh F.Fill GrnMangoCandy(200X3.5G)PR',     1800.00,   1.50),
  ('Fresh F.Fill Coffee Candy(200X3.5G)PR',        1801.00,   1.50),
  ('Fresh F.Fill Coffee Candy Pouch 50(3g x50)',     1442.31,   1.44),
  ('Fresh F.Fill Lychee Candy(200X3.5G)PR',      1800.00,   1.50),
  ('Fresh F.Fill Orange Candy(200X3.5G)PR',      1801.00,   1.50),
  ('Fresh Crispee Milk Wafer 12g(3x24)',            271.11,   3.77),
  ('Fresh Crispee Chocolate Wafer 12g(3x24)',       281.54,   3.91),
  ('Fresh Crispee Coconut Wafer 12g(3x24)',         271.11,   3.77),
  ('Fresh Crispee Strawberry Wafer 12G(3X24)',      274.50,   3.81),
  ('Fresh Crispee Strawberry Wafer 90G(3X24)',      972.00,  27.00),
  ('Fresh Crispee Choc Wafer-Jar 20G (4X20)',       622.70,   7.78),
  ('Fresh Crispee Coco Wafer-Jar 20G (4X20)',       609.52,   7.62),
  ('Fresh Crispee Milk Wafer-Jar 20G (4X20)',       609.52,   7.62),
  ('Fresh Chocolate Bar-Box 12.5g (8X24)',         1382.40,   7.20),
  ('Fresh Chocolate Bar-Box 6.4g (12X36)',         1658.88,   3.84),
  ('Fresh Crispe Choc Mldg Wfr-Box 30g(6X24)',     2073.60,  14.40),
  ('Fresh Crispe Sandwch Wfr Bisct 20g(4X24)',      765.92,   7.98),
  ('Fresh Crispee Choc Coated-Jar 8.5g (6X36)',     879.36,   4.07),
  ('Fresh Crispee Choc Coated-Jar 20g (4X24)',      737.28,   7.68),
  ('Fresh Crispee Choc Coated-Jar4g (6X150)',      1440.00,   1.60),
  ('Fresh Chanachur 22g (8X24)',                   1520.64,   7.92),
  ('Fresh Jhal Chanachur 22g (8x24)',              1520.64,   7.92),
  ('Fresh BBQ Chanachur 22g (8X24)',               1520.64,   7.92),
  ('Fresh BBQ Chanachur 150g (4x10)',              1640.00,  41.00),
  ('Fresh Chanachur 150g (4x10)',                  1640.00,  41.00),
  ('Fresh Jhal Chanachur 150g (4x10)',             1640.00,  41.00),
  ('Fresh BBQ Chanachur 300g (4x5)',               1640.00,  82.00),
  ('Fresh Chanachur 300g(5x4)',                    1640.00,  82.00),
  ('Fresh Jhal Chanachur 300g(5x4)',               1640.00,  82.00);

-- Case, spaces and punctuation vary between the sheet and the catalog.
CREATE OR REPLACE FUNCTION pg_temp._norm(t TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$ SELECT lower(regexp_replace(COALESCE(t, ''), '[^a-zA-Z0-9]', '', 'g')); $$;

DO $$
DECLARE
  v_problem TEXT;
BEGIN
  SELECT string_agg(e.name, E'\n  ') INTO v_problem
    FROM _fresh_etp e
   WHERE NOT EXISTS (
     SELECT 1 FROM public.products p JOIN public.companies c ON c.id = p.company_id
      WHERE c.name = 'Fresh' AND pg_temp._norm(p.name) = pg_temp._norm(e.name));
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION E'no catalog product matches these sheet rows:\n  %', v_problem;
  END IF;

  -- Three catalog products aren't on the sheet: Fresh Chocolate Cookies
  -- 200gX8, and the two Choc/Choc Coco Wafer jars (distinct from the Crispee
  -- ones, which are listed). They keep no ETP, and product_unit_dp falls back
  -- to costing them against their DP as before — deliberately not fatal, so
  -- one unlisted product can't hold up the whole price update.
END $$;

UPDATE public.products p
   SET etp_per_carton = e.etp_ctn,
       etp_per_pcs = e.etp_pcs
  FROM _fresh_etp e
 WHERE pg_temp._norm(p.name) = pg_temp._norm(e.name);
