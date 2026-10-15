-- ============================================================================
-- The Owner gives one selling price per product: the box/jar price. The piece
-- and carton prices have to follow from it, or the three disagree — selling
-- 20 pieces of M&S 20pcs tray brought in 20 x ৳10.70 = ৳214 while the box they
-- came out of sells for ৳220.
--
--   box    = the Owner's price where given, else the vendor's jar price
--   piece  = box / pieces in a box
--   carton = box x boxes in a carton   (already the case)
--
-- Applied to every Pran product with a box level, not only the ones priced by
-- hand. The vendor's own per-piece figures are rounded and drift a couple of
-- taka against their carton — M&S Small tube's carton is ৳1,434 while 192
-- pieces at ৳7.48 come to ৳1,436.16 — so deriving them all keeps the three
-- prices telling one story.
-- ============================================================================
UPDATE public.product_units pcs
   SET price = ROUND(jar.price / (p.factor::NUMERIC / p.jar_per_carton), 2),
       updated_at = now()
  FROM public.products p
  JOIN public.companies c ON c.id = p.company_id
  JOIN public.product_units jar ON jar.product_id = p.id AND jar.unit_type = 'jar'
 WHERE pcs.product_id = p.id
   AND pcs.unit_type = 'pcs'
   AND c.name = 'Pran Chocolate'
   AND p.jar_per_carton IS NOT NULL;

-- ============================================================================
-- The three prices must now tell the same story: a carton's worth of pieces
-- should be worth what the carton is, give or take rounding on the piece.
-- ============================================================================
DO $$
DECLARE
  v_problem TEXT;
BEGIN
  SELECT string_agg(format('%s (carton %s vs %s pieces at %s = %s)',
                           p.name, ctn.price, p.factor, pcs.price,
                           round(pcs.price * p.factor, 2)), ', ')
    INTO v_problem
    FROM public.products p
    JOIN public.companies c ON c.id = p.company_id
    JOIN public.product_units ctn ON ctn.product_id = p.id AND ctn.unit_type = 'carton'
    JOIN public.product_units pcs ON pcs.product_id = p.id AND pcs.unit_type = 'pcs'
   WHERE c.name = 'Pran Chocolate'
     AND p.jar_per_carton IS NOT NULL
     -- A piece rounded to the paisa can drift by up to half a paisa per piece.
     AND abs(pcs.price * p.factor - ctn.price) > GREATEST(1, p.factor * 0.005);
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'piece and carton prices disagree: %', v_problem;
  END IF;

  SELECT string_agg(format('%s %s sells at %s but costs %s',
                           p.name, pu.unit_type, pu.price,
                           round(public.product_unit_dp(pu.product_id, pu.unit_type), 2)), ', ')
    INTO v_problem
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
    JOIN public.companies c ON c.id = p.company_id
   WHERE c.name = 'Pran Chocolate'
     AND pu.price < public.product_unit_dp(pu.product_id, pu.unit_type);
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'these Pran units would sell at a loss: %', v_problem;
  END IF;
END $$;
