-- ============================================================================
-- Fresh Chanachur / Jhal Chanachur / BBQ Chanachur 22g (8X24) order as poli
-- (24 pcs/poli, 8 poli/carton) — poli price = per-piece TP × pcs-per-poli,
-- same derivation used for the "-Box" items.
-- ============================================================================
INSERT INTO public.product_units (product_id, unit_type, price)
SELECT id, 'poli', per_pcs_tp_price * 24 FROM public.products
WHERE company_id = (SELECT id FROM public.companies WHERE name = 'Fresh')
  AND name IN (
    'Fresh Chanachur 22g (8X24)',
    'Fresh Jhal Chanachur 22g (8x24)',
    'Fresh BBQ Chanachur 22g (8X24)'
  )
ON CONFLICT (product_id, unit_type) DO UPDATE SET price = EXCLUDED.price;
