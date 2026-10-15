-- ============================================================================
-- Pran products the Owner hasn't set a selling price for now sell at exactly
-- the After Trade TP.
--
-- They were carrying the sheet's own jar figure, which is rounded and sits a
-- few paisa either side of the per-piece figure the cost is derived from —
-- M&S Small tube's jar read ৳239 against a ৳239.36 basis, its carton ৳1,434
-- against ৳1,436.16. Small, but it meant products nobody had priced showed a
-- stray positive or negative extra profit instead of none at all.
--
-- Selling at trade price is the sensible default: the extra profit is zero
-- and the earning on the line is the company's 6%, which is exactly what
-- happens when goods move at the price the company set.
--
-- Fresh is untouched: its basis is the DP, and selling at DP would mean no
-- margin at all rather than a trade-price sale.
-- ============================================================================
UPDATE public.product_units pu
   SET price = ROUND(public.product_unit_dp(pu.product_id, pu.unit_type), 2),
       updated_at = now()
  FROM public.products p
  JOIN public.companies c ON c.id = p.company_id
 WHERE pu.product_id = p.id
   AND c.name = 'Pran Chocolate'
   AND public.product_unit_dp(pu.product_id, pu.unit_type) IS NOT NULL
   -- The twenty the Owner priced by hand keep their own figure.
   AND p.item_code NOT IN (
     '34242','45228','52199','52238','52283','52349','52675','52714','52989',
     '53123','53285','53705','72022','72985','74059','74091','74093','74349',
     '74460','74496'
   );

-- ============================================================================
-- Those lines should now show no extra profit at all.
-- ============================================================================
DO $$
DECLARE
  v_problem TEXT;
BEGIN
  SELECT string_agg(format('%s %s (%s vs %s)', p.name, pu.unit_type, pu.price,
                           round(public.product_unit_dp(pu.product_id, pu.unit_type), 2)), ', ')
    INTO v_problem
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
    JOIN public.companies c ON c.id = p.company_id
   WHERE c.name = 'Pran Chocolate'
     AND p.item_code NOT IN (
       '34242','45228','52199','52238','52283','52349','52675','52714','52989',
       '53123','53285','53705','72022','72985','74059','74091','74093','74349',
       '74460','74496')
     AND abs(pu.price - public.product_unit_dp(pu.product_id, pu.unit_type)) > 0.01;
  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'these unpriced units still differ from the trade price: %', v_problem;
  END IF;
END $$;
