-- ============================================================================
-- stock_in() only ever adds — there was no way to fix a mistyped quantity.
-- correct_stock() lets the Owner directly set the correct available/damaged
-- numbers for a product+unit. Unlike stock_in, this doesn't go through
-- stock_ins (that log is a record of physical receipts, not corrections) —
-- accountability instead comes from a new audit_stock trigger, so every
-- correction (before/after values, who, when) shows up on the existing
-- Audit Log screen like any other change.
-- ============================================================================
CREATE TRIGGER audit_stock AFTER INSERT OR UPDATE ON public.stock
FOR EACH ROW EXECUTE FUNCTION public.audit_trigger();

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

  INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
  VALUES (p_product_id, p_unit_type, p_available_qty, p_damaged_qty)
  ON CONFLICT (product_id, unit_type) DO UPDATE
    SET available_qty = EXCLUDED.available_qty, damaged_qty = EXCLUDED.damaged_qty, updated_at = now();
END;
$$;
GRANT EXECUTE ON FUNCTION public.correct_stock(UUID, public.unit_type, INTEGER, INTEGER) TO authenticated;
