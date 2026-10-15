-- ============================================================================
-- "Fresh Crispe Sandwich Wfr Bisct 20g(4X24)" (my transcription of the sheet)
-- and "Fresh Crispe Sandwch Wfr Bisct 20g(4X24)" (added later, matching the
-- Owner's actual sheet spelling, with its own corrected pcs/carton/box
-- pricing already set) are the same real product. Drop my mistranscribed
-- duplicate — it has no stock or order history, so nothing is lost.
-- ============================================================================
DELETE FROM public.products WHERE name = 'Fresh Crispe Sandwich Wfr Bisct 20g(4X24)';

-- ============================================================================
-- Two more "-Box" packaged items get the same box-unit treatment (box price
-- = per-piece TP × pcs-per-box), matching Crispe Choc Mldg Wfr and the
-- Sandwich wafer above.
-- ============================================================================
INSERT INTO public.product_units (product_id, unit_type, price)
SELECT id, 'box', 172.80 FROM public.products
WHERE company_id = (SELECT id FROM public.companies WHERE name = 'Fresh')
  AND name = 'Fresh Chocolate Bar-Box 12.5g (8X24)'
ON CONFLICT (product_id, unit_type) DO UPDATE SET price = EXCLUDED.price;

INSERT INTO public.product_units (product_id, unit_type, price)
SELECT id, 'box', 138.24 FROM public.products
WHERE company_id = (SELECT id FROM public.companies WHERE name = 'Fresh')
  AND name = 'Fresh Chocolate Bar-Box 6.4g (12X36)'
ON CONFLICT (product_id, unit_type) DO UPDATE SET price = EXCLUDED.price;

INSERT INTO public.product_units (product_id, unit_type, price)
SELECT id, 'box', 345.60 FROM public.products
WHERE company_id = (SELECT id FROM public.companies WHERE name = 'Fresh')
  AND name = 'Fresh Crispe Choc Mldg Wfr-Box 30g(6X24)'
ON CONFLICT (product_id, unit_type) DO UPDATE SET price = EXCLUDED.price;
