-- ============================================================================
-- The existing "loose units roll up into full cartons" behavior only ever
-- applied to pcs (via products.pcs_per_carton). Poli-tracked products (the
-- Chanachur line) need the same thing: stocking in / ordering enough poli
-- rolls full cartons into the carton count, leaving the remainder as poli.
-- Ratio is per-product (22g = 8 poli/carton, 150g/300g = 4 poli/carton), so
-- this is a new poli_per_carton column, not a hardcoded constant.
-- ============================================================================
ALTER TABLE public.products
  ADD COLUMN poli_per_carton INTEGER CHECK (poli_per_carton IS NULL OR poli_per_carton > 0);

UPDATE public.products SET poli_per_carton = 8
  WHERE company_id = (SELECT id FROM public.companies WHERE name = 'Fresh')
    AND name IN ('Fresh Chanachur 22g (8X24)', 'Fresh Jhal Chanachur 22g (8x24)', 'Fresh BBQ Chanachur 22g (8X24)');

UPDATE public.products SET poli_per_carton = 4
  WHERE company_id = (SELECT id FROM public.companies WHERE name = 'Fresh')
    AND name IN (
      'Fresh Chanachur 150g (4x10)', 'Fresh Jhal Chanachur 150g (4x10)', 'Fresh BBQ Chanachur 150g (4x10)',
      'Fresh BBQ Chanachur 300g (4x5)', 'Fresh Chanachur 300g(5x4)', 'Fresh Jhal Chanachur 300g(5x4)'
    );

-- ============================================================================
-- stock_in — same pcs rollup as before, plus the equivalent poli rollup.
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
  ELSIF p_unit_type = 'poli' AND v_poli_per_carton IS NOT NULL THEN
    v_full_cartons := p_quantity / v_poli_per_carton;
    v_remainder := p_quantity % v_poli_per_carton;

    IF v_full_cartons > 0 THEN
      INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
      VALUES (p_product_id, 'carton', v_full_cartons, 0)
      ON CONFLICT (product_id, unit_type) DO UPDATE
        SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
    END IF;
    IF v_remainder > 0 THEN
      INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
      VALUES (p_product_id, 'poli', v_remainder, 0)
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

-- ============================================================================
-- _apply_summary_item — same rollup applied to what a salesman orders, so
-- ordering 4+ poli also records as a carton line, consistent with stock-in.
-- ============================================================================
CREATE OR REPLACE FUNCTION public._apply_summary_item(
  p_summary_id UUID,
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_quantity INTEGER,
  p_company_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_pcs_per_carton INTEGER;
  v_poli_per_carton INTEGER;
  v_full_cartons INTEGER;
  v_remainder INTEGER;
  v_carton_price NUMERIC(12,2);
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be positive';
  END IF;

  IF p_unit_type = 'pcs' OR p_unit_type = 'poli' THEN
    SELECT pcs_per_carton, poli_per_carton INTO v_pcs_per_carton, v_poli_per_carton
      FROM public.products WHERE id = p_product_id;

    IF p_unit_type = 'pcs' AND v_pcs_per_carton IS NOT NULL AND p_quantity >= v_pcs_per_carton THEN
      SELECT pu.price INTO v_carton_price
        FROM public.product_units pu
        JOIN public.products p ON p.id = pu.product_id
        WHERE pu.product_id = p_product_id AND pu.unit_type = 'carton' AND p.is_active;

      IF v_carton_price IS NOT NULL THEN
        v_full_cartons := p_quantity / v_pcs_per_carton;
        v_remainder := p_quantity % v_pcs_per_carton;

        PERFORM public._upsert_summary_item(p_summary_id, p_product_id, 'carton', v_full_cartons, p_company_id);
        IF v_remainder > 0 THEN
          PERFORM public._upsert_summary_item(p_summary_id, p_product_id, 'pcs', v_remainder, p_company_id);
        END IF;
        RETURN;
      END IF;
    ELSIF p_unit_type = 'poli' AND v_poli_per_carton IS NOT NULL AND p_quantity >= v_poli_per_carton THEN
      SELECT pu.price INTO v_carton_price
        FROM public.product_units pu
        JOIN public.products p ON p.id = pu.product_id
        WHERE pu.product_id = p_product_id AND pu.unit_type = 'carton' AND p.is_active;

      IF v_carton_price IS NOT NULL THEN
        v_full_cartons := p_quantity / v_poli_per_carton;
        v_remainder := p_quantity % v_poli_per_carton;

        PERFORM public._upsert_summary_item(p_summary_id, p_product_id, 'carton', v_full_cartons, p_company_id);
        IF v_remainder > 0 THEN
          PERFORM public._upsert_summary_item(p_summary_id, p_product_id, 'poli', v_remainder, p_company_id);
        END IF;
        RETURN;
      END IF;
    END IF;
  END IF;

  PERFORM public._upsert_summary_item(p_summary_id, p_product_id, p_unit_type, p_quantity, p_company_id);
END;
$$;
