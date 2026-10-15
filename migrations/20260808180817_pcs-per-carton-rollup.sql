-- Bring back a per-product "pieces per carton" number, but scoped narrowly:
-- it's optional (NULL = product has no known carton size), and it only
-- affects how a pcs-unit stock-in gets counted — full multiples roll up
-- into the carton bucket, the remainder stays as loose pieces. Stocking in
-- directly as jar or carton is unaffected (still goes straight into that
-- unit's own bucket, per the fully-independent model). Deliveries and
-- returns are also unaffected — they move exactly the unit that was
-- ordered/returned, never re-split.
ALTER TABLE public.products
  ADD COLUMN pcs_per_carton INTEGER CHECK (pcs_per_carton IS NULL OR pcs_per_carton > 0);

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
  v_full_cartons INTEGER;
  v_remainder INTEGER;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'owner' THEN
    RAISE EXCEPTION 'only the owner can record stock-in';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be positive';
  END IF;

  SELECT pcs_per_carton INTO v_pcs_per_carton FROM public.products WHERE id = p_product_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product not found';
  END IF;

  -- The received-history log always reflects exactly what was physically
  -- received, in the unit it was received in.
  INSERT INTO public.stock_ins (product_id, unit_type, quantity, entry_date, entered_by)
  VALUES (p_product_id, p_unit_type, p_quantity, p_entry_date, auth.uid())
  RETURNING id INTO v_id;

  IF p_unit_type = 'pcs' AND v_pcs_per_carton IS NOT NULL THEN
    v_full_cartons := p_quantity / v_pcs_per_carton;
    v_remainder := p_quantity % v_pcs_per_carton;

    IF v_full_cartons > 0 THEN
      INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
      VALUES (p_product_id, 'carton', v_full_cartons, 0)
      ON CONFLICT (product_id, unit_type) DO UPDATE
        SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
    END IF;
    IF v_remainder > 0 THEN
      INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
      VALUES (p_product_id, 'pcs', v_remainder, 0)
      ON CONFLICT (product_id, unit_type) DO UPDATE
        SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
    END IF;
  ELSE
    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (p_product_id, p_unit_type, p_quantity, 0)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
  END IF;

  RETURN v_id;
END;
$$;
