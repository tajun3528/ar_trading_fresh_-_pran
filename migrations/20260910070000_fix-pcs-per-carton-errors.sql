-- ============================================================================
-- Two pieces-per-carton settings were wrong, which is what made the Stock
-- page look like it was reporting phantom loose pieces.
--
--   Butter Cookies Jar-8X500G  had 6, should be 8
--     "8X500G" is 8 to a carton, and both prices agree exactly:
--     TP 960 / 120 = 8, DP 905.66 / 113.21 = 8.
--
--   Chocolate Chip Cookies 200gX8  had 448, should be 8
--     448 is that product's carton price — the price was typed into the
--     count. "200gX8" is 8 to a carton and TP 448 / 56 = 8.
--
-- Left uncorrected, loose pieces of these two would never have rolled up
-- into cartons no matter how many accumulated.
-- ============================================================================
UPDATE public.products SET pcs_per_carton = 8
 WHERE name = 'Fresh Butter Cookies Jar-8X500G' AND pcs_per_carton = 6;

UPDATE public.products SET pcs_per_carton = 8
 WHERE name = 'Fresh Chocolate Chip Cookies 200gX8' AND pcs_per_carton = 448;

-- Both corrections lower the threshold, so any loose stock that should now
-- be a carton has to be rolled up — the same invariant stock_in() maintains.
DO $$
DECLARE
  r RECORD;
  v_full_cartons INTEGER;
  v_remainder INTEGER;
BEGIN
  FOR r IN
    SELECT s.product_id, s.available_qty, p.pcs_per_carton
      FROM public.stock s
      JOIN public.products p ON p.id = s.product_id
     WHERE s.unit_type = 'pcs'
       AND p.pcs_per_carton IS NOT NULL
       AND s.available_qty >= p.pcs_per_carton
  LOOP
    v_full_cartons := r.available_qty / r.pcs_per_carton;
    v_remainder := r.available_qty % r.pcs_per_carton;

    UPDATE public.stock SET available_qty = v_remainder, updated_at = now()
     WHERE product_id = r.product_id AND unit_type = 'pcs';

    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (r.product_id, 'carton', v_full_cartons, 0)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
  END LOOP;
END $$;
