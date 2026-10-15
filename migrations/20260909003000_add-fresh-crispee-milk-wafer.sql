-- ============================================================================
-- Missed during the initial Fresh price-list import: "Crispee Milk Wafer-Jar
-- 20G (4X20)" is a distinct 4th flavor alongside the already-imported "Choc
-- Wafer", "Choc Coco Wafer", and "Crispee Choc Wafer" at the same price tier.
-- ============================================================================
DO $$
DECLARE
  v_company_id UUID;
  v_category_id UUID;
  v_product_id UUID;
BEGIN
  SELECT id INTO v_company_id FROM public.companies WHERE name = 'Fresh';
  SELECT id INTO v_category_id FROM public.categories
    WHERE name = 'Chocolate & Chocolate Coated' AND company_id = v_company_id;

  INSERT INTO public.products (
    name, category_id, company_id, low_stock_threshold, pcs_per_carton,
    dp_price, tp_price, mrp_price, per_pcs_dp_price, mrp_price_per_pcs,
    trade_note, so_note, after_trade_tp_price, per_pcs_tp_price, erm_percent
  ) VALUES (
    'Fresh Crispee Milk Wafer-Jar 20G (4X20)', v_category_id, v_company_id, 0, 80,
    596.00, 640.00, 800.00, 7.45, 10.00,
    'ETP Rate', NULL, 609.52, 7.62, 31
  ) RETURNING id INTO v_product_id;

  INSERT INTO public.product_units (product_id, unit_type, price) VALUES
    (v_product_id, 'carton', 640.00),
    (v_product_id, 'pcs', 8.00);
END $$;
