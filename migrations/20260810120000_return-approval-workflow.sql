-- ============================================================================
-- Damage and undelivered-return reports now require Owner approval before
-- they touch stock. Previously record_return() applied to stock immediately
-- on insert; a deliveryman's own report (self-attested, no second check)
-- could silently move stock. Now record_return() only files a pending
-- report; a new approve_return()/reject_return() pair (Owner-only) is what
-- actually applies the effect:
--   - damaged  -> approval adds to stock.damaged_qty
--   - good (undelivered, still resellable) -> approval merges back into
--     stock.available_qty, same bucket as normal stock
-- ============================================================================

CREATE TYPE public.return_status AS ENUM ('pending', 'approved', 'rejected');

ALTER TABLE public.returns
  ADD COLUMN status public.return_status NOT NULL DEFAULT 'pending',
  ADD COLUMN approved_by UUID REFERENCES public.profiles(user_id),
  ADD COLUMN approved_at TIMESTAMPTZ;

-- ============================================================================
-- record_return — files a pending report only. No stock effect until an
-- owner approves it.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.record_return(
  p_product_id UUID,
  p_unit_type public.unit_type,
  p_quantity INTEGER,
  p_condition public.return_condition,
  p_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_return_id UUID;
BEGIN
  IF public.current_role() NOT IN ('owner', 'deliveryman') THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'quantity must be positive';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = p_product_id) THEN
    RAISE EXCEPTION 'product not found';
  END IF;

  INSERT INTO public.returns (product_id, unit_type, quantity, condition, reason, return_date, recorded_by, status)
  VALUES (p_product_id, p_unit_type, p_quantity, p_condition, p_reason, current_date, auth.uid(), 'pending')
  RETURNING id INTO v_return_id;

  RETURN v_return_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_return(UUID, public.unit_type, INTEGER, public.return_condition, TEXT) TO authenticated;

-- ============================================================================
-- approve_return — Owner-only. Applies the stock effect exactly once
-- (guarded by the pending-status check) and marks who/when approved.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.approve_return(p_return_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_return public.returns;
BEGIN
  IF public.current_role() != 'owner' THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT * INTO v_return FROM public.returns WHERE id = p_return_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'return not found';
  END IF;
  IF v_return.status != 'pending' THEN
    RAISE EXCEPTION 'return is already %', v_return.status;
  END IF;

  IF v_return.condition = 'good' THEN
    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (v_return.product_id, v_return.unit_type, v_return.quantity, 0)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
  ELSE
    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (v_return.product_id, v_return.unit_type, 0, v_return.quantity)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET damaged_qty = public.stock.damaged_qty + EXCLUDED.damaged_qty, updated_at = now();
  END IF;

  UPDATE public.returns
    SET status = 'approved', approved_by = auth.uid(), approved_at = now()
    WHERE id = p_return_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_return(UUID) TO authenticated;

-- ============================================================================
-- reject_return — Owner-only. No stock effect; just records the decision.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.reject_return(p_return_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_status public.return_status;
BEGIN
  IF public.current_role() != 'owner' THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT status INTO v_status FROM public.returns WHERE id = p_return_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'return not found';
  END IF;
  IF v_status != 'pending' THEN
    RAISE EXCEPTION 'return is already %', v_status;
  END IF;

  UPDATE public.returns
    SET status = 'rejected', approved_by = auth.uid(), approved_at = now()
    WHERE id = p_return_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reject_return(UUID) TO authenticated;
