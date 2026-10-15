-- ============================================================================
-- Approval failed with "insufficient pcs stock" on orders that were perfectly
-- fillable, because nothing in the data ever opened a carton.
--
-- The order screen counts a carton as the pieces inside it — 24 cartons of
-- Sugar Crush is 576 orderable pieces — which is right, since the warehouse
-- can break one open. Approval, though, deducted from the literal pcs row,
-- found 0 loose pieces sitting there, and refused.
--
-- So approval now does what the warehouse does: when loose units fall short,
-- it opens as many cartons as it needs, moving pcs_per_carton (or the poli /
-- jar / box equivalent) units into the loose bucket first. The leftover stays
-- loose, and is always less than one carton — the same invariant stock-in
-- maintains.
--
-- Cartons themselves are never composed out of loose units here: that is the
-- rollup direction, and it already happens when stock is taken in.
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
  v_available INTEGER;
  v_per_carton INTEGER;
  v_cartons_available INTEGER;
  v_shortfall INTEGER;
  v_cartons_needed INTEGER;
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
    SELECT di.delivered_quantity, dsi.product_id, dsi.unit_type,
           p.name AS product_name,
           p.pcs_per_carton, p.poli_per_carton, p.jar_per_carton, p.box_per_carton
      FROM public.delivery_items di
      JOIN public.daily_summary_items dsi ON dsi.id = di.summary_item_id
      JOIN public.products p ON p.id = dsi.product_id
     WHERE di.delivery_id = p_delivery_id AND di.delivered_quantity > 0
     -- Cartons first, so a carton line is served before any of it is broken
     -- open for loose units of the same product.
     ORDER BY (dsi.unit_type = 'carton') DESC
  LOOP
    SELECT available_qty INTO v_available FROM public.stock
      WHERE product_id = v_item.product_id AND unit_type = v_item.unit_type FOR UPDATE;
    v_available := COALESCE(v_available, 0);

    IF v_available < v_item.delivered_quantity AND v_item.unit_type <> 'carton' THEN
      v_per_carton := CASE v_item.unit_type
        WHEN 'pcs' THEN v_item.pcs_per_carton
        WHEN 'poli' THEN v_item.poli_per_carton
        WHEN 'jar' THEN v_item.jar_per_carton
        WHEN 'box' THEN v_item.box_per_carton
      END;

      IF v_per_carton IS NOT NULL AND v_per_carton > 0 THEN
        v_shortfall := v_item.delivered_quantity - v_available;
        v_cartons_needed := CEIL(v_shortfall::NUMERIC / v_per_carton)::INTEGER;

        SELECT available_qty INTO v_cartons_available FROM public.stock
          WHERE product_id = v_item.product_id AND unit_type = 'carton' FOR UPDATE;
        v_cartons_available := COALESCE(v_cartons_available, 0);

        IF v_cartons_available >= v_cartons_needed THEN
          UPDATE public.stock
             SET available_qty = available_qty - v_cartons_needed, updated_at = now()
           WHERE product_id = v_item.product_id AND unit_type = 'carton';

          INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
          VALUES (v_item.product_id, v_item.unit_type, v_cartons_needed * v_per_carton, 0)
          ON CONFLICT (product_id, unit_type) DO UPDATE
            SET available_qty = public.stock.available_qty + EXCLUDED.available_qty, updated_at = now();

          v_available := v_available + v_cartons_needed * v_per_carton;
        END IF;
      END IF;
    END IF;

    IF v_available < v_item.delivered_quantity THEN
      RAISE EXCEPTION 'not enough % of % — need %, have %',
        v_item.unit_type, v_item.product_name, v_item.delivered_quantity, v_available;
    END IF;

    INSERT INTO public.stock (product_id, unit_type, available_qty, damaged_qty)
    VALUES (v_item.product_id, v_item.unit_type, 0, 0)
    ON CONFLICT (product_id, unit_type) DO NOTHING;

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
