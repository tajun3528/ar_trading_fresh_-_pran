-- ============================================================================
-- stock_in()'s pcs/poli-per-carton rollup only ever looked at the quantity
-- being added in THAT call, never the pieces already sitting in stock — so
-- three separate stock-ins of 10 pcs each (30 total, above a 24-per-carton
-- threshold) never rolled over, even though a single stock-in of 30 would
-- have. Fix: roll up against (existing stock + new quantity) combined, and
-- SET the remainder rather than adding to it, so the pcs/poli bucket never
-- sits above its own per-carton threshold after a stock-in.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.stock_in(
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_quantity INTEGER,
  p_entry_date DATE DEFAULT current_date
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_id UUID;
  v_pcs_per_carton INTEGER;
  v_poli_per_carton INTEGER;
  v_per_carton INTEGER;
  v_existing_qty INTEGER;
  v_new_total INTEGER;
  v_full_cartons INTEGER;
  v_remainder INTEGER;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'only the owner can record stock-in';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be positive';
  END IF;

  SELECT pcs_per_carton, poli_per_carton INTO v_pcs_per_carton, v_poli_per_carton
    FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product not found';
  END IF;

  -- The received-history log always reflects exactly what was physically
  -- received, in the unit it was received in.
  INSERT INTO public.stock_ins (product_id, unit_type, quantity, entry_date, entered_by)
  VALUES (p_product_id, p_unit_type, p_quantity, p_entry_date, auth.uid())
  RETURNING id INTO v_id;

  v_per_carton := CASE p_unit_type
    WHEN 'pcs' THEN v_pcs_per_carton
    WHEN 'poli' THEN v_poli_per_carton
    ELSE NULL
  END;

  IF v_per_carton IS NOT NULL THEN
    SELECT available_qty INTO v_existing_qty FROM public.stock
      WHERE product_id = p_product_id AND unit_type = p_unit_type FOR UPDATE;
    v_new_total := COALESCE(v_existing_qty, 0) + p_quantity;
    v_full_cartons := v_new_total / v_per_carton;
    v_remainder := v_new_total % v_per_carton;

    IF v_full_cartons > 0 THEN
      INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
      VALUES (p_product_id, 'carton', v_full_cartons, 0)
      ON CONFLICT (product_id, unit_type) DO UPDATE
        SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
    END IF;

    -- SET (not add) — this is the corrected running total for the loose
    -- unit, already accounting for whatever was there before this call.
    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (p_product_id, p_unit_type, v_remainder, 0)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET available_qty = v_remainder, updated_at = now();
  ELSE
    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (p_product_id, p_unit_type, p_quantity, 0)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
  END IF;

  RETURN v_id;
END;
$$;

-- ============================================================================
-- One-time correction for stock that accumulated under the old, buggy
-- per-call-only rollup: "Fresh Fun.Fill Milk Crm Biscuits-24X35G" has 29
-- loose pcs sitting unrolled (pcs_per_carton = 24) — roll it to +1 carton,
-- 5 pcs remainder, matching what stock_in() would now produce.
-- ============================================================================
DO $$
DECLARE
  v_product_id UUID;
BEGIN
  SELECT id INTO v_product_id FROM public.products WHERE name = 'Fresh Fun.Fill Milk Crm Biscuits-24X35G';

  UPDATE public.stock SET available_qty = 5, updated_at = now()
    WHERE product_id = v_product_id AND unit_type = 'pcs';

  INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
  VALUES (v_product_id, 'carton', 1, 0)
  ON CONFLICT (product_id, unit_type) DO UPDATE
    SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
END $$;
