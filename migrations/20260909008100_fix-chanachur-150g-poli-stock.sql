-- ============================================================================
-- This stock-in happened before poli_per_carton rollup existed: 4 poli were
-- recorded as loose poli instead of rolling up into 1 carton (4 poli/carton
-- for the 150g tier). One-time correction to match what stock_in() would
-- now do.
-- ============================================================================
UPDATE public.stock SET available_qty = 0, updated_at = now()
WHERE unit_type = 'poli'
  AND product_id = (SELECT id FROM public.products WHERE name = 'Fresh Chanachur 150g (4x10)');

INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
SELECT id, 'carton', 1, 0 FROM public.products WHERE name = 'Fresh Chanachur 150g (4x10)'
ON CONFLICT (product_id, unit_type) DO UPDATE
  SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
