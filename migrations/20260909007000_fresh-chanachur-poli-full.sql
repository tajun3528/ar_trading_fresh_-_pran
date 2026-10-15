-- ============================================================================
-- Complete the 3-flavor × 3-size Chanachur grid (missed "BBQ 150g" during
-- the initial import) and apply poli pricing across the 150g and 300g
-- tiers (the 22g tier was already done). Poli price = per-piece TP ×
-- pcs-per-poli, same derivation as the box items.
-- ============================================================================
DO $$
DECLARE
  v_company_id UUID;
  v_category_id UUID;
  v_product_id UUID;
BEGIN
  SELECT id INTO v_company_id FROM public.companies WHERE name = 'Fresh';
  SELECT id INTO v_category_id FROM public.categories WHERE name = 'Snacks' AND company_id = v_company_id;

  -- Missing product: same numbers as its Chanachur/Jhal 150g siblings.
  INSERT INTO public.products (
    name, category_id, company_id, low_stock_threshold, pcs_per_carton,
    dp_price, tp_price, mrp_price, per_pcs_dp_price, mrp_price_per_pcs,
    trade_note, so_note, after_trade_tp_price, per_pcs_tp_price, erm_percent
  ) VALUES (
    'Fresh BBQ Chanachur 150g (4x10)', v_category_id, v_company_id, 0, 40,
    1546.00, 1640.00, 2000.00, 38.65, 50.00,
    NULL, NULL, 1640.00, 41.00, 22
  ) RETURNING id INTO v_product_id;

  INSERT INTO public.product_units (product_id, unit_type, price) VALUES
    (v_product_id, 'carton', 1640.00),
    (v_product_id, 'pcs', 41.00);

  -- 150g tier: 4 poli/carton, 10 pcs/poli — poli price = 41.00 * 10.
  INSERT INTO public.product_units (product_id, unit_type, price)
  SELECT id, 'poli', 410.00 FROM public.products
  WHERE company_id = v_company_id
    AND name IN (
      'Fresh Chanachur 150g (4x10)',
      'Fresh Jhal Chanachur 150g (4x10)',
      'Fresh BBQ Chanachur 150g (4x10)'
    )
  ON CONFLICT (product_id, unit_type) DO UPDATE SET price = EXCLUDED.price;

  -- 300g tier: confirmed 4 poli/carton, 5 pcs/poli for all three flavors
  -- (BBQ's own name already said 4x5; Chanachur/Jhal's "(5x4)" naming was
  -- just written in the opposite digit order for the same physical pack).
  INSERT INTO public.product_units (product_id, unit_type, price)
  SELECT id, 'poli', 405.00 FROM public.products
  WHERE company_id = v_company_id
    AND name IN (
      'Fresh BBQ Chanachur 300g (4x5)',
      'Fresh Chanachur 300g(5x4)',
      'Fresh Jhal Chanachur 300g(5x4)'
    )
  ON CONFLICT (product_id, unit_type) DO UPDATE SET price = EXCLUDED.price;
END $$;
