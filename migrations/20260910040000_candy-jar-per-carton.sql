-- ============================================================================
-- The Candy jars were the last units left without a DP cost, so sales of them
-- showed no profit.
--
-- Candy has been 6 jars to a carton since that category was converted to
-- jar/carton pricing, but jar_per_carton didn't exist then — only the prices
-- were set. The count confirms itself against those prices: carton TP 1800 /
-- jar TP 300 = 6, and carton DP 1698 / 6 = 283 leaves 17 margin a jar, which
-- is exactly the 102 carton margin split six ways.
-- ============================================================================
UPDATE public.products p
   SET jar_per_carton = 6
  FROM public.categories c
 WHERE c.id = p.category_id
   AND c.name = 'Candy'
   AND EXISTS (
     SELECT 1 FROM public.product_units pu WHERE pu.product_id = p.id AND pu.unit_type = 'jar'
   );

-- Every priced unit should now cost something. Failing here beats shipping a
-- catalog that silently reports zero profit on whatever was missed.
DO $$
DECLARE
  v_missing TEXT;
BEGIN
  SELECT string_agg(format('%s (%s)', p.name, pu.unit_type), ', ')
    INTO v_missing
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
   WHERE public.product_unit_dp(pu.product_id, pu.unit_type) IS NULL;

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'these priced units still have no DP cost: %', v_missing;
  END IF;
END $$;
