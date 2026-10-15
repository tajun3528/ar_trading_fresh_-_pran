-- ============================================================================
-- Pran Chocolate's initial catalog, from the vendor price sheet the Owner
-- shared. All items land in one 'General' category — the Owner can split
-- them into finer categories later via the existing Products screen, same
-- as any other product.
--
-- Every item gets exactly one product_units row (unit_type='carton', the
-- app's "single pack unit" slot for trade_pricing companies) priced at the
-- sheet's TP — that's the price submit_daily_summary/edit_daily_summary
-- actually charge. DP/MRP/After-Trade/Per-pcs figures are stored on
-- products as Owner-facing reference data only.
-- ============================================================================
DO $$
DECLARE
  v_company_id UUID;
  v_category_id UUID;
BEGIN
  SELECT id INTO v_company_id FROM public.companies WHERE name = 'Pran Chocolate';

  INSERT INTO public.categories (name, company_id) VALUES ('General', v_company_id)
  RETURNING id INTO v_category_id;

  INSERT INTO public.products (
    name, category_id, company_id, low_stock_threshold,
    item_code, factor, dp_price, tp_price, mrp_price, sku_qty, trade_qty, jar_box_size,
    after_trade_dp_price, after_trade_tp_price, per_pcs_dp_price, per_pcs_tp_price
  )
  SELECT
    v.name, v_category_id, v_company_id, 0,
    v.item_code, v.factor, v.dp_price, v.tp_price, v.mrp_price, v.sku_qty, v.trade_qty, v.jar_box_size,
    v.after_trade_dp_price, v.after_trade_tp_price, v.per_pcs_dp_price, v.per_pcs_tp_price
  FROM (VALUES
    ('34241', 'M&S Small tube-32pcs', 192, 7.50, 8.00, 10, 32, 2, 32, 226, 239, 7.06, 7.48),
    ('34242', 'M&S 20pcs tray', 240, 10.60, 11.30, 15, 20, 1, 20, 202, 214, 10.10, 10.70),
    ('34248', 'PRAN Glucose D 400g box', 12, 115, 125, 150, 24, 1, 24, 2650, 2809, 110.40, 117.02),
    ('34773', 'PRAN Lollipop Orange 100 Pcs', 600, 3.75, 4.00, 5, 100, 15, 100, 326, 346, 3.26, 3.46),
    ('45228', 'M&S Chain-N', 288, 4.00, 4.25, 5, 288, 21, 24, 89, 95, 3.73, 3.95),
    ('50698', 'M&S Baby feeder Small', 150, 14, 15, 20, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ('52238', 'Pran Lollipop Sports Series (100pcs x 6 Jar)', 600, 4.00, 4.25, 5, 100, 12, 100, 357, 379, 3.57, 3.79),
    ('52283', 'Fruitfil Litchi 200 pcs X 15Jar', 3000, 1.56, 1.66, 2, 200, 20, 200, 284, 301, 1.42, 1.50),
    ('52293', 'PRAN Pulse Candy Mango 200pcs x 12 Jar', 2400, 1.50, 1.60, 2, 200, 34, 200, 256, 272, 1.28, 1.36),
    ('52349', 'Fruto Candy Milk 300pcs jar', 4500, 0.85, 0.90, 1, 300, 38, 300, 226, 240, 0.75, 0.80),
    ('52714', 'PRAN Chew Candy Assorted 150pcs container', 1800, 1.50, 1.60, 2, 150, 27, 150, 191, 202, 1.27, 1.35),
    ('52989', 'SIPCO ORANGO Tasty Saline 20 Pcs X 12 Box', 240, 5.00, 5.20, 6, 240, 10, 20, 96, 102, 4.80, 5.09),
    ('53285', 'PRAN Jelly Candy 200pcs X 15Jar', 3000, 1.50, 1.60, 2, 200, 20, 200, 273, 289, 1.36, 1.45),
    ('53705', 'Hurray Choco Egg 45pcs jar', 270, 7.50, 8.00, 10, 270, 12, 45, 323, 343, 7.18, 7.61),
    ('72354', 'KENSINGTON ORANGE FLV CREAMY WAFER BIS 24pcs', 12, 38.25, 40.00, 50, 24, 1, 1, 37, 39, 36.72, 38.92),
    ('72480', 'Eyedrop Ball Candy 50pcs x 6 Jar', 300, 7.00, 7.50, 10, 50, 12, 50, 282, 299, 5.65, 5.98),
    ('74010', 'Treat Coco Choco Coconut Bar 8Pcs Box', 240, 4.00, 4.25, 5, 8, 1, 8, 28, 30, 3.56, 3.77),
    ('74059', 'PRAN Choco Choco Cookies & Cream 80pcs container', 1440, 3.18, 3.37, 5, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ('74349', 'Premio Choco Card 25g X 5 Pcs X 24 Pack', 12, 75, 80, 100, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ('47312', 'Buddy wafer Milk Mega 20 pcs Jar', 80, 8.00, 8.50, 10, 20, 1, 20, 152, 162, 7.62, 8.08),
    ('47341', 'Buddy wafer Chocolate mini 25 Pcs Jar', 375, 4.00, 4.25, 5, 25, 1, 25, 96, 102, 3.85, 4.08),
    ('72044', 'Hurray Pillow Wafer Chocolate 20g X 24Pcs X 2 Pouch', 48, 7.50, 8.00, 10, 96, 3, 24, 175, 185, 7.27, 7.71),
    ('72022', 'Treat Cone Wafer 25 Pcs X 6 Jar', 150, 14, 15, 20, 300, 12, 25, 337, 357, 13.46, 14.27),
    ('52199', 'PRAN Éclair Strawberry 300pcs jar', 3600, 0.85, 0.90, 1, 300, 25, 300, 235, 250, 0.78, 0.83),
    ('74093', 'Chao Chao Mini Assorted Chain Lollipop 72pcs x 12', 864, 2.37, 2.52, 3, 72, 7, 72, 156, 165, 2.16, 2.29),
    ('72923', 'Starlight Candy Cane 50pcs x 12 Jar-A', 600, 2.37, 2.52, 3, 50, 13, 50, 94, 100, 1.88, 1.99),
    ('72921', 'Whirly Lollipop Love Shape 30pcs x 12 Jar', 360, 7.00, 7.50, 10, 30, 4, 30, 185, 196, 6.18, 6.55),
    ('74496', 'Bro Crispy Peanut Bar 50 Pcs x 12 Jar', 600, 4.00, 4.25, 5, 50, 5, 30, 109, 116, 3.64, 3.85),
    ('74467', 'Pran Lolipop Love Series 100 Pcs x 6 jar', 600, 3.75, 4.00, 5, 100, 15, 100, 326, 346, 3.26, 3.46),
    ('74498', 'Treat Chocolate 30 pcs Jar', 450, 7.50, 8.00, 10, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ('72059', 'Divino Chocolate Bar 150gm', 40, 150, 160, 200, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ('74468', 'Pran Biggy Assorted Lollipop Twist 30 Pcs x 8 Jar', 240, 7.50, 8.00, 10, 30, 4, 100, 662, 701, 6.62, 7.01),
    ('74460', 'PRAN Jelly Bear Cup 20pcs X 6jar', 120, 7.55, 8.00, 10, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ('72983', 'Crimson Éclair Double Love-105g box', 30, 93, 100, 130, 30, 2, 30, 2616, 2773, 87.19, 92.42),
    ('72985', 'Crimson Éclair Octagonal Box-135g box', 12, 140, 150, 200, 12, 1, 12, 1551, 1644, 129.23, 136.98),
    ('72984', 'Crimson Éclair Round Box-135g box', 24, 126, 135, 180, 24, 2, 24, 2791, 2959, 116.31, 123.29),
    ('34227', 'Fruitfil Litchi 75 pcs', 2400, 1.50, 1.60, 2, 75, 8, 75, 102, 108, 1.36, 1.44),
    ('74091', 'Hurray Chocolate Coated Wafer 35 Pcs X 6 Jar', 210, 4.00, 4.25, 5, 210, 11, 35, 133, 141, 3.80, 4.03),
    ('52675', 'SmileyEat 16pcs x 8jar', 128, 22.56, 24.00, 30, 128, 11, 30, 623, 661, 20.77, 22.02),
    ('48414', 'Treat Coffee Chocolate Bar 20gm Cereal', 240, 14.00, 15.00, 20, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ('31632', 'Treat Dairy Milk-12.5gm', 216, 8.00, 8.50, 10, 24, 2, 24, 177, 188, 7.38, 7.83),
    ('53123', 'Hurray My Love Wafer 10 Pcs X 12 Jar', 120, 8.00, 8.50, 10, 10, 1, 10, 73, 77, 7.27, 7.71),
    ('74506', 'Chao Chao Lollipop Bucket 100 Pcs x 8 Jar', 800, 3.75, 4.00, 5, NULL, NULL, NULL, NULL, NULL, NULL, NULL)
  ) AS v(item_code, name, factor, dp_price, tp_price, mrp_price, sku_qty, trade_qty, jar_box_size,
         after_trade_dp_price, after_trade_tp_price, per_pcs_dp_price, per_pcs_tp_price);

  INSERT INTO public.product_units (product_id, unit_type, price)
  SELECT id, 'carton', tp_price FROM public.products WHERE company_id = v_company_id;
END $$;
