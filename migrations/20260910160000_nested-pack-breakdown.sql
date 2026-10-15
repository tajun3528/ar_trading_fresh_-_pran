-- ============================================================================
-- Packaging nests three deep, and only two levels were being honoured.
--
-- "Fresh Chocolate Bar-Box 12.5g (8X24)" is 8 boxes to a carton and 24 pieces
-- to a box. Stock held 1 carton and 4 loose boxes, but box availability was
-- read straight off the box bucket — 4 — because only pieces and poli were
-- ever derived from cartons. The true figure is 4 + (1 x 8) = 12.
--
-- Approval had the matching gap: it could open a carton, but never a box. So
-- a product sitting on loose boxes with no cartons could show pieces as
-- available and then refuse to approve.
--
-- _ensure_unit_stock breaks packaging down the way a storeman would: take a
-- loose box before opening a carton, and open a carton into boxes rather than
-- straight into a heap of loose pieces, so the shelf still reads correctly
-- afterwards.
-- ============================================================================
CREATE OR REPLACE FUNCTION public._ensure_unit_stock(
  p_product_id UUID,
  p_unit public.unit_type,
  p_needed INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  p RECORD;
  v_avail INTEGER;
  v_cartons INTEGER;
  v_short INTEGER;
  v_per_carton INTEGER;
  v_cartons_needed INTEGER;
  v_mid public.unit_type;
  v_mid_per_carton INTEGER;
  v_pcs_per_mid INTEGER;
  v_mid_stock INTEGER;
  v_take INTEGER;
  v_pass INTEGER;
BEGIN
  SELECT pcs_per_carton, poli_per_carton, jar_per_carton, box_per_carton
    INTO p FROM public.products WHERE id = p_product_id;

  SELECT COALESCE(available_qty, 0) INTO v_avail FROM public.stock
    WHERE product_id = p_product_id AND unit_type = p_unit FOR UPDATE;
  v_avail := COALESCE(v_avail, 0);
  IF v_avail >= p_needed THEN
    RETURN true;
  END IF;
  IF p_unit = 'carton' THEN
    RETURN false;  -- cartons are never assembled out of loose units here
  END IF;

  -- Which mid-size pack, if any, this product uses between carton and piece.
  IF p.box_per_carton IS NOT NULL AND p.box_per_carton > 0 THEN
    v_mid := 'box'; v_mid_per_carton := p.box_per_carton;
  ELSIF p.jar_per_carton IS NOT NULL AND p.jar_per_carton > 0 THEN
    v_mid := 'jar'; v_mid_per_carton := p.jar_per_carton;
  ELSIF p.poli_per_carton IS NOT NULL AND p.poli_per_carton > 0 THEN
    v_mid := 'poli'; v_mid_per_carton := p.poli_per_carton;
  END IF;

  v_per_carton := CASE p_unit
    WHEN 'pcs' THEN p.pcs_per_carton
    WHEN 'poli' THEN p.poli_per_carton
    WHEN 'jar' THEN p.jar_per_carton
    WHEN 'box' THEN p.box_per_carton
  END;

  -- A mid-size pack only ever comes out of a carton.
  IF p_unit <> 'pcs' THEN
    IF v_per_carton IS NULL OR v_per_carton <= 0 THEN
      RETURN false;
    END IF;
    SELECT COALESCE(available_qty, 0) INTO v_cartons FROM public.stock
      WHERE product_id = p_product_id AND unit_type = 'carton' FOR UPDATE;
    v_cartons := COALESCE(v_cartons, 0);

    v_short := p_needed - v_avail;
    v_cartons_needed := CEIL(v_short::NUMERIC / v_per_carton)::INTEGER;
    IF v_cartons < v_cartons_needed THEN
      RETURN false;
    END IF;

    UPDATE public.stock SET available_qty = available_qty - v_cartons_needed, updated_at = now()
      WHERE product_id = p_product_id AND unit_type = 'carton';
    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (p_product_id, p_unit, v_cartons_needed * v_per_carton, 0)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
    RETURN true;
  END IF;

  -- Pieces: take loose mid packs first, then open cartons into mid packs and
  -- take from those. Two passes is enough — the second runs with whatever the
  -- opened cartons produced.
  IF p.pcs_per_carton IS NULL OR p.pcs_per_carton <= 0 THEN
    RETURN false;
  END IF;

  IF v_mid IS NULL THEN
    -- No mid pack: a carton opens straight into loose pieces.
    SELECT COALESCE(available_qty, 0) INTO v_cartons FROM public.stock
      WHERE product_id = p_product_id AND unit_type = 'carton' FOR UPDATE;
    v_cartons := COALESCE(v_cartons, 0);
    v_short := p_needed - v_avail;
    v_cartons_needed := CEIL(v_short::NUMERIC / p.pcs_per_carton)::INTEGER;
    IF v_cartons < v_cartons_needed THEN
      RETURN false;
    END IF;
    UPDATE public.stock SET available_qty = available_qty - v_cartons_needed, updated_at = now()
      WHERE product_id = p_product_id AND unit_type = 'carton';
    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (p_product_id, 'pcs', v_cartons_needed * p.pcs_per_carton, 0)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
    RETURN true;
  END IF;

  v_pcs_per_mid := p.pcs_per_carton / v_mid_per_carton;
  IF v_pcs_per_mid <= 0 THEN
    RETURN false;
  END IF;

  FOR v_pass IN 1..2 LOOP
    v_short := p_needed - v_avail;
    EXIT WHEN v_short <= 0;

    SELECT COALESCE(available_qty, 0) INTO v_mid_stock FROM public.stock
      WHERE product_id = p_product_id AND unit_type = v_mid FOR UPDATE;
    v_mid_stock := COALESCE(v_mid_stock, 0);

    v_take := LEAST(v_mid_stock, CEIL(v_short::NUMERIC / v_pcs_per_mid)::INTEGER);
    IF v_take > 0 THEN
      UPDATE public.stock SET available_qty = available_qty - v_take, updated_at = now()
        WHERE product_id = p_product_id AND unit_type = v_mid;
      INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
      VALUES (p_product_id, 'pcs', v_take * v_pcs_per_mid, 0)
      ON CONFLICT (product_id, unit_type) DO UPDATE
        SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
      v_avail := v_avail + v_take * v_pcs_per_mid;
      v_short := p_needed - v_avail;
    END IF;

    EXIT WHEN v_short <= 0;
    EXIT WHEN v_pass = 2;

    -- Still short: open cartons into mid packs and let the next pass take
    -- pieces from them.
    SELECT COALESCE(available_qty, 0) INTO v_cartons FROM public.stock
      WHERE product_id = p_product_id AND unit_type = 'carton' FOR UPDATE;
    v_cartons := COALESCE(v_cartons, 0);
    EXIT WHEN v_cartons <= 0;

    v_cartons_needed := LEAST(v_cartons, CEIL(v_short::NUMERIC / p.pcs_per_carton)::INTEGER);
    UPDATE public.stock SET available_qty = available_qty - v_cartons_needed, updated_at = now()
      WHERE product_id = p_product_id AND unit_type = 'carton';
    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (p_product_id, v_mid, v_cartons_needed * v_mid_per_carton, 0)
    ON CONFLICT (product_id, unit_type) DO UPDATE
      SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();
  END LOOP;

  RETURN v_avail >= p_needed;
END;
$$;

-- ============================================================================
-- approve_delivery — defers the whole "is there enough, and what has to be
-- opened" question to the routine above.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.approve_delivery(p_delivery_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_delivery RECORD;
  v_item RECORD;
BEGIN
  IF public.current_role() != 'owner' THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT * INTO v_delivery FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF v_delivery IS NULL THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;
  IF v_delivery.approval_status != 'pending' THEN
    RAISE EXCEPTION 'delivery is already %', v_delivery.approval_status;
  END IF;
  IF v_delivery.loaded_at IS NOT NULL AND v_delivery.returns_recorded_at IS NULL THEN
    RAISE EXCEPTION 'this round is still out — the deliveryman has not recorded returns yet';
  END IF;

  FOR v_item IN
    SELECT di.delivered_quantity, dsi.product_id, dsi.unit_type, p.name AS product_name
      FROM public.delivery_items di
      JOIN public.daily_summary_items dsi ON dsi.id = di.summary_item_id
      JOIN public.products p ON p.id = dsi.product_id
     WHERE di.delivery_id = p_delivery_id AND di.delivered_quantity > 0
     -- Biggest units first: a carton line is served before anything gets
     -- opened up for the smaller units of the same product.
     ORDER BY CASE dsi.unit_type
                WHEN 'carton' THEN 0 WHEN 'box' THEN 1 WHEN 'jar' THEN 2
                WHEN 'poli' THEN 3 ELSE 4 END
  LOOP
    IF NOT public._ensure_unit_stock(v_item.product_id, v_item.unit_type, v_item.delivered_quantity) THEN
      RAISE EXCEPTION 'not enough % of % — need %',
        v_item.unit_type, v_item.product_name, v_item.delivered_quantity;
    END IF;

    UPDATE public.stock
       SET available_qty = available_qty - v_item.delivered_quantity, updated_at = now()
     WHERE product_id = v_item.product_id AND unit_type = v_item.unit_type;
  END LOOP;

  UPDATE public.daily_summaries SET status = v_delivery.status, updated_at = now() WHERE id = v_delivery.summary_id;
  UPDATE public.deliveries
    SET approval_status = 'approved', approved_by = auth.uid(), approved_at = now()
    WHERE id = p_delivery_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.approve_delivery(UUID) TO authenticated;
