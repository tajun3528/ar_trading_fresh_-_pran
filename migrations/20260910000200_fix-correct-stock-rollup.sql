-- ============================================================================
-- correct_stock() (Product Detail's manual stock-correction dialog) directly
-- SETs whatever the Owner types, with no carton rollup at all — so
-- correcting pcs/poli to a number above that product's per-carton threshold
-- left it sitting there un-rolled, the same class of bug just fixed in
-- stock_in() and the order flow. Damaged quantity is left as a direct set
-- either way — damaged goods are a defect count, not something that gets
-- repackaged into cartons.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.correct_stock(
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_available_qty INTEGER,
  p_damaged_qty INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_pcs_per_carton INTEGER;
  v_poli_per_carton INTEGER;
  v_per_carton INTEGER;
  v_full_cartons INTEGER;
  v_remainder INTEGER;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'only the owner can correct stock';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = p_product_id) THEN
    RAISE EXCEPTION 'product not found';
  END IF;
  IF p_available_qty IS NULL OR p_available_qty < 0 THEN
    RAISE EXCEPTION 'available quantity must not be negative';
  END IF;
  IF p_damaged_qty IS NULL OR p_damaged_qty < 0 THEN
    RAISE EXCEPTION 'damaged quantity must not be negative';
  END IF;

  SELECT pcs_per_carton, poli_per_carton INTO v_pcs_per_carton, v_poli_per_carton
    FROM public.products WHERE id = p_product_id;
  v_per_carton := CASE p_unit_type
    WHEN 'pcs' THEN v_pcs_per_carton
    WHEN 'poli' THEN v_poli_per_carton
    ELSE NULL
  END;

  IF v_per_carton IS NOT NULL AND p_available_qty >= v_per_carton THEN
    v_full_cartons := p_available_qty / v_per_carton;
    v_remainder := p_available_qty % v_per_carton;

    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (p_product_id, 'carton', v_full_cartons, 0)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();

    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (p_product_id, p_unit_type, v_remainder, p_damaged_qty)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET available_qty = v_remainder, damaged_qty = EXCLUDED.damaged_qty, updated_at = now();
  ELSE
    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (p_product_id, p_unit_type, p_available_qty, p_damaged_qty)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET available_qty = EXCLUDED.available_qty, damaged_qty = EXCLUDED.damaged_qty, updated_at = now();
  END IF;
END;
$$;
