-- ============================================================================
-- Every product in Chocolate & Chocolate Coated is sold by the box, so each
-- one gets a box price and a boxes-per-carton count.
--
-- The count is the first number in the pack size on the vendor's sheet — a
-- (4X20) carton holds 4 boxes of 20 — and the box price is the carton price
-- divided by that, per the Owner. Deriving from the carton price rather than
-- the piece price is deliberate: for the 90G wafer the sheet's second number
-- (24) isn't its pieces-per-box (36 per carton ÷ 3 = 12), so piece-based
-- arithmetic would be wrong there while carton-based stays right.
--
-- boxes_per_carton is set for all 17, including those already priced, since
-- the profit calculation needs it to work out what one box costs.
-- ============================================================================
CREATE TEMP TABLE _choc_boxes (name TEXT PRIMARY KEY, boxes_per_carton INTEGER) ON COMMIT DROP;

INSERT INTO _choc_boxes (name, boxes_per_carton) VALUES
  ('Fresh Choc Coco Wafer-Jar 20G (4X20)',      4),
  ('Fresh Choc Wafer-Jar 20G (4X20)',           4),
  ('Fresh Chocolate Bar-Box 12.5g (8X24)',      8),
  ('Fresh Chocolate Bar-Box 6.4g (12X36)',      12),
  ('Fresh Crispe Choc Mldg Wfr-Box 30g(6X24)',  6),
  ('Fresh Crispe Sandwch Wfr Bisct 20g(4X24)',  4),
  ('Fresh Crispee Choc Coated-Jar 20g (4X24)',  4),
  ('Fresh Crispee Choc Coated-Jar 8.5g (6X36)', 6),
  ('Fresh Crispee Choc Coated-Jar4g (6X150)',   6),
  ('Fresh Crispee Choc Wafer-Jar 20G (4X20)',   4),
  ('Fresh Crispee Chocolate Wafer 12g(3x24)',   3),
  ('Fresh Crispee Coco Wafer-Jar 20G (4X20',    4),
  ('Fresh Crispee Coconut Wafer 12g(3x24)',     3),
  ('Fresh Crispee Milk Wafer 12g(3x24)',        3),
  ('Fresh Crispee Milk Wafer-Jar 20G (4X20)',   4),
  ('Fresh Crispee Strawberry Wafer 12g(3X24)',  3),
  ('Fresh Crispee Strawberry Wafer 90G(3X24)',  3);

-- Guard against a rename drifting this list out of sync with the catalog:
-- silently skipping a product would leave it without a box unit.
DO $$
DECLARE
  v_missing TEXT;
BEGIN
  SELECT string_agg(b.name, ', ') INTO v_missing
    FROM _choc_boxes b
    WHERE NOT EXISTS (SELECT 1 FROM public.products p WHERE p.name = b.name);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'these products no longer exist under these names: %', v_missing;
  END IF;
END $$;

UPDATE public.products p
   SET box_per_carton = b.boxes_per_carton
  FROM _choc_boxes b
 WHERE p.name = b.name;

-- Box price = carton price / boxes per carton, for the ones not already priced.
INSERT INTO public.product_units (product_id, unit_type, price)
SELECT p.id, 'box', round(cu.price / b.boxes_per_carton, 2)
  FROM _choc_boxes b
  JOIN public.products p ON p.name = b.name
  JOIN public.product_units cu ON cu.product_id = p.id AND cu.unit_type = 'carton'
 WHERE NOT EXISTS (
   SELECT 1 FROM public.product_units pu WHERE pu.product_id = p.id AND pu.unit_type = 'box'
 );

-- ============================================================================
-- Two corrections the Owner confirmed while reviewing this category.
--
-- 1. "Crispee Choc Coated-Jar 20g (4X24)" had a box price of 160 — the figure
--    its (4X20) shelf-mates carry — but a 24-piece box at 8.00 is 192, which
--    is also carton 768 / 4.
-- 2. "Crispee Coco Wafer-Jar 20G (4X20" had 596 pieces per carton; every
--    other (4X20) product has 80, and 80 x 8.00 matches its 640 carton price.
--    The wrong figure would have mis-rolled loose pieces into cartons and
--    understated the per-piece DP cost.
-- ============================================================================
UPDATE public.product_units pu
   SET price = 192.00, updated_at = now()
  FROM public.products p
 WHERE p.id = pu.product_id
   AND p.name = 'Fresh Crispee Choc Coated-Jar 20g (4X24)'
   AND pu.unit_type = 'box';

UPDATE public.products
   SET pcs_per_carton = 80
 WHERE name = 'Fresh Crispee Coco Wafer-Jar 20G (4X20';
