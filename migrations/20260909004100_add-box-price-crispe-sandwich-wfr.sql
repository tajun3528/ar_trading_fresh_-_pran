-- ============================================================================
-- "Fresh Crispe Sandwich Wfr Bisct 20g(4X24)" orders as a box (24 pcs/box,
-- 4 boxes/carton) — add the box price alongside its existing carton/pcs
-- prices (all three stay independently orderable/stockable).
-- ============================================================================
INSERT INTO public.product_units (product_id, unit_type, price)
SELECT id, 'box', 196.80 FROM public.products
WHERE company_id = (SELECT id FROM public.companies WHERE name = 'Fresh')
  AND name = 'Fresh Crispe Sandwich Wfr Bisct 20g(4X24)'
ON CONFLICT (product_id, unit_type) DO UPDATE SET price = EXCLUDED.price;
