-- ============================================================================
-- Fresh's real catalog, from the "PL-G, September 2026" vendor price list the
-- Owner shared (7 sections become 7 categories). Each product gets both a
-- carton and a pcs product_units row (TP/CTN, TP/PCS) — that's the live,
-- editable selling price used by every order RPC. DP/MRP/Trade/SO/ETP/ERM
-- columns are Owner-facing reference data only, exactly as with Pran
-- Chocolate's price sheet.
-- ============================================================================
CREATE TEMP TABLE _fresh_import (
  category TEXT,
  name TEXT,
  ctn_fac INTEGER,
  dp_ctn NUMERIC,
  dp_pcs NUMERIC,
  tp_ctn NUMERIC,
  tp_pcs NUMERIC,
  mrp_ctn NUMERIC,
  mrp_pcs NUMERIC,
  trade_note TEXT,
  so_note TEXT,
  etp_ctn NUMERIC,
  etp_pcs NUMERIC,
  erm NUMERIC
);

INSERT INTO _fresh_import
  (category, name, ctn_fac, dp_ctn, dp_pcs, tp_ctn, tp_pcs, mrp_ctn, mrp_pcs, trade_note, so_note, etp_ctn, etp_pcs, erm)
VALUES
  ('5 Tk. Biscuits', 'Fresh F.Sndwch Crm Pineapple-48X17G', 48, 192.45, 4.01, 204, 4.25, 240, 5, '3PCS/CTN', '16CTN/1CTN', 192.00, 4.00, 25),
  ('5 Tk. Biscuits', 'Fresh F.Sndwch Crm Choc Bist-48X17G', 48, 192.45, 4.01, 204, 4.25, 240, 5, '3PCS/CTN', '16CTN/1CTN', 204.00, 4.25, 18),
  ('5 Tk. Biscuits', 'Fresh Potatoz Spicy Biscuit-13GX72', 72, 271.70, 3.77, 288, 4.00, 360, 5, '4PCS/CTN', '18CTN/1CTN', 272.84, 3.79, 32),
  ('5 Tk. Biscuits', 'Fresh Sugar Crush Biscuit 17GX48', 48, 181.13, 3.77, 192, 4.00, 240, 5, '3PCS/CTN', '16CTN/1CTN', 192.00, 4.00, 25),
  ('5 Tk. Biscuits', 'Fresh Lexus Vegetables Crackers 48x15g', 48, 181.13, 3.77, 192, 4.00, 240, 5, '2PCS/CTN', '16CTN/1CTN', 180.71, 3.76, 33),
  ('5 Tk. Biscuits', 'Fresh Energy Power Biscuit 16gx48', 48, 181.13, 3.77, 192, 4.00, 240, 5, '2PCS/CTN', '24CTN/1CTN', 184.32, 3.84, 30),
  ('5 Tk. Biscuits', 'Fresh Fun.Fill Milk Crm Biscuits-48X17G', 48, 192.45, 4.01, 204, 4.25, 240, 5, '3PCS/CTN', '16CTN/1CTN', 192.00, 4.00, 25),

  ('10 Tk. Biscuits', 'Fresh Orangy Biscuit-24X38G', 24, 183.96, 7.67, 195, 8.13, 240, 10, '1PCS/CTN', '24CTN/1CTN', 187.20, 7.80, 28),
  ('10 Tk. Biscuits', 'Fresh Energy Power Biscuit 40gX24', 24, 192.45, 8.02, 204, 8.50, 240, 10, '1.5PCS/CTN', '16CTN/1CTN', 192.00, 8.00, 25),
  ('10 Tk. Biscuits', 'Fresh Sweet n Salty Biscuit 37gx24', 24, 183.96, 7.67, 195, 8.13, 240, 10, '1PCS/CTN', '24CTN/1CTN', 195.00, 8.13, 23),
  ('10 Tk. Biscuits', 'Fresh Sugar Crush Biscuit 34gx24', 24, 183.96, 7.67, 195, 8.13, 240, 10, '1.5PCS/CTN', '16CTN/1CTN', 183.53, 7.65, 31),
  ('10 Tk. Biscuits', 'Fresh Milk Shakti Biscuit 40gx24', 24, 181.13, 7.55, 192, 8.00, 240, 10, '3PCS/CTN', '24CTN/1CTN', 192.00, 8.00, 25),
  ('10 Tk. Biscuits', 'Fresh F.Sndwch Crm Choc Bist-24X34G', 24, 192.45, 8.02, 204, 8.50, 240, 10, '1PCS/CTN', '24CTN/1CTN', 195.84, 8.16, 25),
  ('10 Tk. Biscuits', 'Fresh Fun.Fill Milk Crm Biscuits-24X35G', 24, 188.68, 7.86, 200, 8.33, 240, 10, '1PCS/CTN', '24CTN/1CTN', 192.00, 8.00, 25),
  ('10 Tk. Biscuits', 'Fresh Dry Cake 24X24G', 48, 362.26, 7.54, 384, 8.00, 480, 10, '2PCS/CTN', '24CTN/1CTN', 368.64, 7.68, 30),

  ('20 Tk. Biscuits', 'Fresh Coconut Cookies-24X72G', 24, 362.26, 15.09, 384, 16.00, 480, 20, '1PCS/CTN', '24CTN/1CTN', 368.64, 15.36, 30),
  ('20 Tk. Biscuits', 'Fresh Super Delicious Biscuit-24X72G', 24, 362.16, 15.09, 384, 16.00, 480, 20, NULL, NULL, 384.00, 16.00, 25),
  ('20 Tk. Biscuits', 'Fresh Potatoz Spicy Biscuit-50GX24', 24, 362.26, 15.09, 384, 16.00, 480, 20, NULL, NULL, 384.00, 16.00, 25),
  ('20 Tk. Biscuits', 'Fresh Twisty Vanilla Cream Biscui-24X50G', 24, 362.16, 15.09, 384, 16.00, 480, 20, NULL, NULL, 384.00, 16.00, 25),
  ('20 Tk. Biscuits', 'Fresh Chocolate Chip Cookies 60GX24', 24, 362.26, 15.09, 384, 16.00, 480, 20, NULL, NULL, 384.00, 16.00, 25),
  ('20 Tk. Biscuits', 'Fresh Choco Love Biscuit-45GX24', 24, 362.26, 15.09, 384, 16.00, 480, 20, NULL, NULL, 384.00, 16.00, 25),
  ('20 Tk. Biscuits', 'Fresh Healthy Choice Salted 80gX24PC', 24, 362.16, 15.09, 384, 16.00, 480, 20, NULL, NULL, 384.00, 16.00, 25),
  ('20 Tk. Biscuits', 'Fresh Lexus Vegetables Crackers 63gx24PC', 24, 362.26, 15.09, 384, 16.00, 480, 20, NULL, NULL, 384.00, 16.00, 25),

  ('Family Biscuits', 'Fresh Orangy Biscuits-8X139G', 8, 252.83, 31.60, 268, 33.50, 320, 40, '1 PC/2CTN', '16CTN/1CTN', 252.24, 31.53, 27),
  ('Family Biscuits', 'Fresh Tea Partner Cookies Biscuit-6X185G', 6, 237.74, 39.62, 252, 42.00, 300, 50, '1PC/2CTN', '12CTN/1CTN', 252.00, 42.00, 19),
  ('Family Biscuits', 'Fresh Energy Power Biscuit 180gx6', 6, 237.74, 39.62, 252, 42.00, 300, 50, NULL, NULL, 232.62, 38.77, 29),
  ('Family Biscuits', 'Fresh Salted Cookies-160GX6', 6, 237.74, 39.62, 252, 42.00, 300, 50, NULL, NULL, 252.00, 42.00, 19),
  ('Family Biscuits', 'Fresh Milk Marie Biscuit 200gX6', 6, 237.74, 39.62, 252, 42.00, 300, 50, NULL, NULL, 252.00, 42.00, 19),
  ('Family Biscuits', 'Fresh Butter Cookies Family -170GX8', 8, 316.98, 39.62, 336, 42.00, 400, 50, '1 PCS/2CTN', '16CTN/1CTN', 316.24, 39.53, 26),
  ('Family Biscuits', 'Fresh Coconut Cookies-185GX8', 8, 316.98, 39.62, 336, 42.00, 400, 50, NULL, NULL, 316.23, 39.53, 26),
  ('Family Biscuits', 'Fresh Coconut Cookies-240GX8', 8, 367.92, 45.99, 390, 48.75, 480, 60, NULL, NULL, 390.00, 48.75, 19),
  ('Family Biscuits', 'Fresh Super Delicious Cookies 160GX8', 8, 316.98, 39.62, 336, 42.00, 400, 50, '1 PCS/2CTN', '16CTN/1CTN', 336.00, 42.00, 19),
  ('Family Biscuits', 'Fresh Chocolate Cookies 200gX8', 8, 422.64, 52.83, 448, 56.00, 560, 70, '1 PCS/2CTN', '16CTN/1CTN', 421.65, 52.71, 25),
  ('Family Biscuits', 'Potatoz Spicy Biscuit-192g-10P', 10, 754.72, 75.47, 800, 80.00, 1000, 100, NULL, NULL, 800.00, 80.00, 20),
  ('Family Biscuits', 'Fresh Lexus Vegetable Crackers 10x180g', 10, 566.00, 56.60, 600, 60.00, 1000, 100, NULL, NULL, 600.00, 60.00, 67),
  ('Family Biscuits', 'Fresh Fantasy Choc Filled Cookis-175GX12', 12, 1304.15, 108.68, 1382.40, 115.20, 1600, 150, NULL, NULL, 1382.40, 115.20, 27),
  ('Family Biscuits', 'Fresh Fantasy Choc Filled Cookies-75GX24', 12, 1149.49, 47.90, 1218.46, 50.77, 1560, 65, NULL, NULL, 1218.40, 50.77, 22),
  ('Family Biscuits', 'Fresh Butter Cookies Jar-8X500G', 6, 905.66, 113.21, 960, 120.00, 1200, 150, NULL, NULL, 960.00, 120.00, 20),
  ('Family Biscuits', 'Fresh Butter Cookies Jar-750GX6', 6, 905.66, 150.94, 960, 160.00, 1200, 200, NULL, NULL, 960.00, 160.00, 20),
  ('Family Biscuits', 'Fresh Fantasy Choc Filled Cookies-Jar 400GX6', 6, 1449.06, 241.51, 1536, 256.00, 1920, 320, NULL, NULL, 1536.00, 256.00, 25),
  ('Family Biscuits', 'Fresh Special Toast Biscuits', 6, 237.92, 39.65, 252, 42.00, 300, 50, NULL, NULL, 252.00, 42.00, 17),
  ('Family Biscuits', 'Fresh Sweet Toast Biscuits', 6, 311.32, 51.89, 330.00, 55.00, 420, 70, NULL, NULL, 330.00, 55.00, 21),

  ('Candy', 'Fresh F.Fill GrnMangoCandy(200X3.5G)PR', 1200, 1698.12, 1.42, 1800, 1.50, 2400, 2.00, 'Tea Cup', NULL, 1800.00, 1.50, 33),
  ('Candy', 'Fresh F.Fill Coffee Candy(200X3.5G)PR', 1200, 1698.00, 1.42, 1800, 1.50, 2400, 2.00, 'Tea Cup', NULL, 1801.00, 1.50, 33),
  ('Candy', 'Fresh F.Fill Coffee Candy Pouch 50(3g x50)', 1000, 1415.00, 1.42, 1500, 1.50, 2000, 2.00, '25:1', NULL, 1441.32, 1.44, 39),
  ('Candy', 'Fresh F.Fill Lychee Candy(200X3.5G)PR', 1200, 1698.00, 1.42, 1800, 1.50, 2400, 2.00, 'Tea Cup', NULL, 1800.00, 1.50, 33),
  ('Candy', 'Fresh F.Fill Orange Candy(200X3.5G)PR', 1200, 1698.00, 1.42, 1801, 1.50, 2400, 2.00, 'Tea Cup', NULL, 1801.00, 1.50, 33),

  ('Chocolate & Chocolate Coated', 'Fresh Crispee Milk Wafer 12g(3x24)', 72, 288.00, 4.00, 305, 4.24, 360, 5, '9PCS/CTN', NULL, 271.11, 3.77, 27),
  ('Chocolate & Chocolate Coated', 'Fresh Crispee Chocolate Wafer 12g(3x24)', 72, 288.00, 4.00, 305, 4.24, 360, 5, '6PCS/CTN', NULL, 281.51, 3.91, 28),
  ('Chocolate & Chocolate Coated', 'Fresh Crispee Coconut Wafer 12g(3x24)', 72, 288.00, 4.00, 305, 4.24, 360, 5, '9PCS/CTN', NULL, 271.11, 3.77, 27),
  ('Chocolate & Chocolate Coated', 'Fresh Crispee Strawberry Wafer 12g(3X24)', 72, 288.00, 4.00, 305, 4.24, 360, 5, '8PCS/CTN', NULL, 274.50, 3.81, 30),
  ('Chocolate & Chocolate Coated', 'Fresh Crispee Strawberry Wafer 90G(3X24)', 36, 966.60, 26.85, 1026, 28.50, 1250, 35, 'ETP Rate', NULL, 972.00, 27.00, 39),
  ('Chocolate & Chocolate Coated', 'Fresh Choc Wafer-Jar 20G (4X20)', 80, 596.00, 7.45, 640, 8.00, 800, 10, 'ETP Rate', NULL, 622.70, 7.78, 26),
  ('Chocolate & Chocolate Coated', 'Fresh Choc Coco Wafer-Jar 20G (4X20)', 80, 596.00, 7.45, 640, 8.00, 800, 10, 'ETP Rate', NULL, 609.52, 7.62, 31),
  ('Chocolate & Chocolate Coated', 'Fresh Crispee Choc Wafer-Jar 20G (4X20)', 80, 596.00, 7.45, 640, 8.00, 800, 10, 'ETP Rate', NULL, 609.52, 7.62, 31),
  ('Chocolate & Chocolate Coated', 'Fresh Chocolate Bar-Box 12.5g (8X24)', 192, 1344.00, 7.00, 1440, 7.50, 1800, 10, 'ETP Rate', NULL, 1382.40, 7.20, 39),
  ('Chocolate & Chocolate Coated', 'Fresh Chocolate Bar-Box 6.4g (12X36)', 432, 1620.00, 3.75, 1728, 4.00, 2160, 5, 'ETP Rate', NULL, 1658.88, 3.84, 30),
  ('Chocolate & Chocolate Coated', 'Fresh Crispee Choc Mldg Wfr-Box 30g(6X24)', 144, 2008.80, 13.95, 2160, 15.00, 2880, 20, 'ETP Rate', NULL, 2073.60, 14.40, 39),
  ('Chocolate & Chocolate Coated', 'Fresh Crispe Sandwich Wfr Bisct 20g(4X24)', 96, 739.20, 7.70, 787, 8.20, 960, 10, 'ETP Rate', NULL, 765.92, 7.98, 25),
  ('Chocolate & Chocolate Coated', 'Fresh Crispee Choc Coated-Jar 8.5g (6X36)', 216, 864.00, 4.00, 916, 4.24, 1080, 5, 'ETP Rate', NULL, 879.36, 4.07, 23),
  ('Chocolate & Chocolate Coated', 'Fresh Crispee Choc Coated-Jar 20g (4X24)', 96, 715.20, 7.45, 768, 8.00, 960, 10, 'ETP Rate', NULL, 737.28, 7.68, 30),
  ('Chocolate & Chocolate Coated', 'Fresh Crispee Choc Coated-Jar4g (6X150)', 900, 1350.00, 1.50, 1440, 1.60, 1800, 2, 'No Trade Offer', NULL, 1440.00, 1.60, 25),

  ('Snacks', 'Fresh Chanachur 22g (8X24)', 192, 1497.60, 7.80, 1584, 8.25, 1920, 10, NULL, NULL, 1520.64, 7.92, 26),
  ('Snacks', 'Fresh Jhal Chanachur 22g (8x24)', 192, 1497.60, 7.80, 1584, 8.25, 1920, 10, NULL, NULL, 1520.64, 7.92, 26),
  ('Snacks', 'Fresh BBQ Chanachur 22g (8X24)', 192, 1497.60, 7.80, 1584, 8.25, 1920, 10, NULL, NULL, 1520.64, 7.92, 26),
  ('Snacks', 'Fresh Chanachur 150g (4x10)', 40, 1546.00, 38.65, 1640, 41.00, 2000, 50, NULL, NULL, 1640.00, 41.00, 22),
  ('Snacks', 'Fresh Jhal Chanachur 150g (4x10)', 40, 1546.00, 38.65, 1640, 41.00, 2000, 50, NULL, NULL, 1640.00, 41.00, 22),
  ('Snacks', 'Fresh BBQ Chanachur 300g (4x5)', 20, 1545.00, 77.25, 1620, 81.00, 2000, 100, NULL, NULL, 1620.00, 81.00, 22),
  ('Snacks', 'Fresh Chanachur 300g(5x4)', 20, 1545.00, 77.25, 1620, 81.00, 2000, 100, NULL, NULL, 1620.00, 81.00, 22),
  ('Snacks', 'Fresh Jhal Chanachur 300g(5x4)', 20, 1545.00, 77.25, 1620, 81.00, 2000, 100, NULL, NULL, 1620.00, 81.00, 22);

DO $$
DECLARE
  v_company_id UUID;
BEGIN
  SELECT id INTO v_company_id FROM public.companies WHERE name = 'Fresh';

  INSERT INTO public.categories (name, company_id)
  SELECT DISTINCT category, v_company_id FROM _fresh_import;

  INSERT INTO public.products (
    name, category_id, company_id, low_stock_threshold, pcs_per_carton,
    dp_price, tp_price, mrp_price, per_pcs_dp_price, mrp_price_per_pcs,
    trade_note, so_note, after_trade_tp_price, per_pcs_tp_price, erm_percent
  )
  SELECT
    f.name, c.id, v_company_id, 0, f.ctn_fac,
    f.dp_ctn, f.tp_ctn, f.mrp_ctn, f.dp_pcs, f.mrp_pcs,
    f.trade_note, f.so_note, f.etp_ctn, f.etp_pcs, f.erm
  FROM _fresh_import f
  JOIN public.categories c ON c.name = f.category AND c.company_id = v_company_id;

  INSERT INTO public.product_units (product_id, unit_type, price)
  SELECT p.id, 'carton', f.tp_ctn
  FROM _fresh_import f
  JOIN public.products p ON p.name = f.name AND p.company_id = v_company_id;

  INSERT INTO public.product_units (product_id, unit_type, price)
  SELECT p.id, 'pcs', f.tp_pcs
  FROM _fresh_import f
  JOIN public.products p ON p.name = f.name AND p.company_id = v_company_id
  WHERE f.tp_pcs IS NOT NULL;
END $$;

DROP TABLE _fresh_import;
