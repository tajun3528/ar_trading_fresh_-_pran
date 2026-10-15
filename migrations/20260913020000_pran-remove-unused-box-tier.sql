-- ============================================================================
-- Two products have no box/jar tier on the Owner's list, and no box price or
-- box stock was ever given for them — they are sold by the carton and the
-- piece only. Their box level was inferred earlier from the pack size and is
-- removed here.
--
--   Treat Coffee Chocolate Bar 20gm Cereal
--   Treat Chocolate 30 pcs Jar
--
-- Everything else on the list already matches, including the three Crimson
-- boxes (12, 30 and 24 boxes to a carton, the box being the sellable piece)
-- and Jelly Bear Cup's 6 jars.
-- ============================================================================
DELETE FROM public.product_units pu
 USING public.products p, public.companies c
 WHERE pu.product_id = p.id
   AND p.company_id = c.id
   AND c.name = 'Pran Chocolate'
   AND pu.unit_type = 'jar'
   AND p.item_code IN ('48414', '74498');

DELETE FROM public.stock s
 USING public.products p, public.companies c
 WHERE s.product_id = p.id
   AND p.company_id = c.id
   AND c.name = 'Pran Chocolate'
   AND s.unit_type = 'jar'
   AND p.item_code IN ('48414', '74498');

UPDATE public.products p
   SET jar_per_carton = NULL
  FROM public.companies c
 WHERE p.company_id = c.id
   AND c.name = 'Pran Chocolate'
   AND p.item_code IN ('48414', '74498');

-- ============================================================================
-- The carton price must still hold now the box tier is gone: it is the piece
-- price across a whole carton.
-- ============================================================================
UPDATE public.product_units ctn
   SET price = ROUND(pcs.price * p.factor, 2), updated_at = now()
  FROM public.products p
  JOIN public.companies c ON c.id = p.company_id
  JOIN public.product_units pcs ON pcs.product_id = p.id AND pcs.unit_type = 'pcs'
 WHERE ctn.product_id = p.id
   AND ctn.unit_type = 'carton'
   AND c.name = 'Pran Chocolate'
   AND p.item_code IN ('48414', '74498');

DO $$
DECLARE
  v_problem TEXT;
BEGIN
  SELECT string_agg(format('%s %s', p.name, pu.unit_type), ', ') INTO v_problem
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
   WHERE public.product_unit_dp(pu.product_id, pu.unit_type) IS NULL
      OR pu.price < public.product_unit_dp(pu.product_id, pu.unit_type) * 0.8;
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'these units have no cost or are priced far below it: %', v_problem;
  END IF;
END $$;
