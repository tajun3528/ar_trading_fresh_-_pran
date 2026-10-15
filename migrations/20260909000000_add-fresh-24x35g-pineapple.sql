-- ============================================================================
-- Missed during the initial Fresh price-list import: "F.Fill Sndwch Crm
-- Pineapple-24X35G" is a distinct product from the already-imported
-- "Fun.Fill Milk Crm Biscuits-24X35G" at the same 10 Tk. price tier.
-- ============================================================================
DO $$
DECLARE
  v_company_id UUID;
  v_category_id UUID;
  v_product_id UUID;
BEGIN
  SELECT id INTO v_company_id FROM public.companies WHERE name = 'Fresh';
  SELECT id INTO v_category_id FROM public.categories WHERE name = '10 Tk. Biscuits' AND company_id = v_company_id;

  INSERT INTO public.products (
    name, category_id, company_id, low_stock_threshold, pcs_per_carton,
    dp_price, tp_price, mrp_price, per_pcs_dp_price, mrp_price_per_pcs,
    trade_note, so_note, after_trade_tp_price, per_pcs_tp_price, erm_percent
  ) VALUES (
    'Fresh F.Fill Sndwch Crm Pineapple-24X35G', v_category_id, v_company_id, 0, 24,
    188.68, 200.00, 240.00, 7.86, 10.00,
    '1PCS/CTN', '24CTN/1CTN', 192.00, 8.00, 25
  ) RETURNING id INTO v_product_id;

  INSERT INTO public.product_units (product_id, unit_type, price) VALUES
    (v_product_id, 'carton', 200.00),
    (v_product_id, 'pcs', 8.33);
END $$;
