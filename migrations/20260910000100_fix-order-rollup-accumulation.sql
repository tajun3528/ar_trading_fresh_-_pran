-- ============================================================================
-- Same bug as stock_in(), on the order side: _apply_summary_item only ever
-- checked the incoming quantity against pcs_per_carton/poli_per_carton, not
-- the pieces already on this summary's line for that product — so three
-- separate 10-pc additions to the same daily summary (30 total, above a
-- 24-per-carton threshold) never rolled into a carton, even though a single
-- 30-pc entry already did (that check was on the incoming quantity alone,
-- which happened to be large enough on its own).
--
-- Fix mirrors stock_in(): roll up against (existing line quantity + new
-- quantity) combined. Needs a new "set to this absolute value" helper
-- alongside the existing additive _upsert_summary_item, since the pcs/poli
-- line's correct new value is a remainder, not something to add to.
-- ============================================================================
CREATE OR REPLACE FUNCTION public._set_summary_item(
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
  v_unit_price NUMERIC(12,2);
  v_existing_item_id UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = p_product_id AND company_id = p_company_id) THEN
    RAISE EXCEPTION 'product does not belong to your assigned company';
  END IF;

  SELECT id INTO v_existing_item_id
    FROM public.daily_summary_items
    WHERE summary_id = p_summary_id AND product_id = p_product_id AND unit_type = p_unit_type
    FOR UPDATE;

  IF p_quantity <= 0 THEN
    IF v_existing_item_id IS NOT NULL THEN
      DELETE FROM public.daily_summary_items WHERE id = v_existing_item_id;
    END IF;
    RETURN;
  END IF;

  SELECT pu.price INTO v_unit_price
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
    WHERE pu.product_id = p_product_id AND pu.unit_type = p_unit_type AND p.is_active;
  IF v_unit_price IS NULL THEN
    RAISE EXCEPTION 'no active price for the given product/unit';
  END IF;

  IF v_existing_item_id IS NOT NULL THEN
    UPDATE public.daily_summary_items
      SET quantity = p_quantity, unit_price = v_unit_price, line_total = v_unit_price * p_quantity
      WHERE id = v_existing_item_id;
  ELSE
    INSERT INTO public.daily_summary_items (summary_id, product_id, unit_type, quantity, unit_price, line_total)
    VALUES (p_summary_id, p_product_id, p_unit_type, p_quantity, v_unit_price, v_unit_price * p_quantity);
  END IF;
END;
$$;

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
  v_per_carton INTEGER;
  v_carton_price NUMERIC(12,2);
  v_existing_qty INTEGER;
  v_new_total INTEGER;
  v_full_cartons INTEGER;
  v_remainder INTEGER;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be positive';
  END IF;

  IF p_unit_type = 'pcs' OR p_unit_type = 'poli' THEN
    SELECT pcs_per_carton, poli_per_carton INTO v_pcs_per_carton, v_poli_per_carton
      FROM public.products WHERE id = p_product_id;
    v_per_carton := CASE p_unit_type WHEN 'pcs' THEN v_pcs_per_carton WHEN 'poli' THEN v_poli_per_carton END;

    IF v_per_carton IS NOT NULL THEN
      SELECT pu.price INTO v_carton_price
        FROM public.product_units pu
        JOIN public.products p ON p.id = pu.product_id
        WHERE pu.product_id = p_product_id AND pu.unit_type = 'carton' AND p.is_active;

      IF v_carton_price IS NOT NULL THEN
        SELECT quantity INTO v_existing_qty FROM public.daily_summary_items
          WHERE summary_id = p_summary_id AND product_id = p_product_id AND unit_type = p_unit_type
          FOR UPDATE;
        v_new_total := COALESCE(v_existing_qty, 0) + p_quantity;

        IF v_new_total >= v_per_carton THEN
          v_full_cartons := v_new_total / v_per_carton;
          v_remainder := v_new_total % v_per_carton;

          -- Cartons accumulate additively across calls (correct on its
          -- own); the pcs/poli line is SET to the remainder so it never
          -- sits above v_per_carton after this call, same invariant as
          -- stock_in()'s fix.
          PERFORM public._upsert_summary_item(p_summary_id, p_product_id, 'carton', v_full_cartons, p_company_id);
          PERFORM public._set_summary_item(p_summary_id, p_product_id, p_unit_type, v_remainder, p_company_id);
          RETURN;
        END IF;
      END IF;
    END IF;
  END IF;

  PERFORM public._upsert_summary_item(p_summary_id, p_product_id, p_unit_type, p_quantity, p_company_id);
END;
$$;
