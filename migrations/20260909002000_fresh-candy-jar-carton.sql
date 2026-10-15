-- ============================================================================
-- Fresh's "(200X3.5G)PR" candy line (GrnMango, Coffee, Lychee, Orange) sells
-- as jar/carton (6 jars per carton, jar ৳300, carton ৳1800), not pcs/carton —
-- "Coffee Candy Pouch 50" is a different pack and is untouched. Coffee Candy
-- itself was already corrected via the app (jar row + stock already exist);
-- this brings the other three in line and drops the now-unused pcs price
-- from all four so pcs can no longer be accidentally ordered.
-- ============================================================================
DO $$
DECLARE
  v_company_id UUID;
  v_product_id UUID;
BEGIN
  SELECT id INTO v_company_id FROM public.companies WHERE name = 'Fresh';

  FOR v_product_id IN
    SELECT id FROM public.products
    WHERE company_id = v_company_id
      AND name IN (
        'Fresh F.Fill GrnMangoCandy(200X3.5G)PR',
        'Fresh F.Fill Coffee Candy(200X3.5G)PR',
        'Fresh F.Fill Lychee Candy(200X3.5G)PR',
        'Fresh F.Fill Orange Candy(200X3.5G)PR'
      )
  LOOP
    INSERT INTO public.product_units (product_id, unit_type, price)
    VALUES (v_product_id, 'jar', 300.00)
    ON CONFLICT (product_id, unit_type) DO UPDATE SET price = EXCLUDED.price;

    INSERT INTO public.product_units (product_id, unit_type, price)
    VALUES (v_product_id, 'carton', 1800.00)
    ON CONFLICT (product_id, unit_type) DO UPDATE SET price = EXCLUDED.price;

    DELETE FROM public.product_units WHERE product_id = v_product_id AND unit_type = 'pcs';

    UPDATE public.products SET pcs_per_carton = NULL, tp_price = 1800.00 WHERE id = v_product_id;
  END LOOP;
END $$;
