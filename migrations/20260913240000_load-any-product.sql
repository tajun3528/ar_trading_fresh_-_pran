-- ============================================================================
-- Loading a product that is not on the order.
--
-- "Load more" could only top up lines the order already had, so putting
-- anything else on the van meant using "Add product" first -- two tools for
-- one action, and the difference was not obvious in a warehouse.
--
-- Now one call takes either: an existing line to top up, or any product of
-- the company to put on the van for the first time.
--
-- A round's lines must reference order lines (delivery_items.summary_item_id
-- is NOT NULL and an order line must have quantity > 0), so loading something
-- new does add it to the order. That is honest rather than awkward: it is
-- going out on this van for this order, and whatever the shops do not buy
-- comes back as a return. No stock moves either way until delivery, so
-- carrying a product speculatively cannot distort the warehouse count.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.load_more_into_van(p_delivery_id UUID, p_items JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $fn$
DECLARE
  v_delivery RECORD;
  v_summary RECORD;
  v_item JSONB;
  v_summary_item RECORD;
  v_product RECORD;
  v_unit public.unit_type;
  v_item_id UUID;
  v_extra INTEGER;
  v_any BOOLEAN := false;
  v_total NUMERIC(12,2);
BEGIN
  SELECT * INTO v_delivery FROM public.deliveries WHERE id = p_delivery_id FOR UPDATE;
  IF v_delivery IS NULL THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;
  IF v_delivery.deliveryman_id <> auth.uid() AND public.current_role() <> 'owner' THEN
    RAISE EXCEPTION 'not your delivery';
  END IF;
  IF v_delivery.loaded_at IS NULL THEN
    RAISE EXCEPTION 'load the van first';
  END IF;
  IF v_delivery.returns_recorded_at IS NOT NULL THEN
    RAISE EXCEPTION 'this round is already closed and waiting on owner approval';
  END IF;

  SELECT * INTO v_summary FROM public.daily_summaries WHERE id = v_delivery.summary_id FOR UPDATE;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) LOOP
    -- How much is being ADDED now, not the new running total, so two people
    -- topping up the same round cannot overwrite each other.
    v_extra := COALESCE((v_item->>'add_quantity')::INTEGER, 0);
    IF v_extra < 0 THEN
      RAISE EXCEPTION 'quantity to add cannot be negative';
    END IF;
    CONTINUE WHEN v_extra = 0;

    IF v_item ? 'summary_item_id' AND NULLIF(v_item->>'summary_item_id', '') IS NOT NULL THEN
      -- Topping up a line the order already has: the order is unchanged, only
      -- more of it goes on the van.
      SELECT * INTO v_summary_item FROM public.daily_summary_items
        WHERE id = (v_item->>'summary_item_id')::UUID AND summary_id = v_delivery.summary_id;
      IF v_summary_item IS NULL THEN
        RAISE EXCEPTION 'that product is not on this order';
      END IF;
      v_item_id := v_summary_item.id;
    ELSE
      -- Anything else in this company's catalog, on the van for the first time.
      v_unit := (v_item->>'unit_type')::public.unit_type;
      SELECT id, company_id INTO v_product FROM public.products
        WHERE id = (v_item->>'product_id')::UUID;
      IF v_product IS NULL THEN
        RAISE EXCEPTION 'product not found';
      END IF;
      IF v_product.company_id IS DISTINCT FROM v_summary.company_id THEN
        RAISE EXCEPTION 'that product belongs to a different company';
      END IF;

      -- Prices and rolls up cartons exactly as a salesman's own line would.
      PERFORM public._apply_summary_item(
        v_delivery.summary_id, v_product.id, v_unit, v_extra, v_summary.company_id);

      SELECT id INTO v_item_id FROM public.daily_summary_items
        WHERE summary_id = v_delivery.summary_id
          AND product_id = v_product.id
          AND unit_type = v_unit;
    END IF;

    v_any := true;

    INSERT INTO public.delivery_items (
      delivery_id, summary_item_id, loaded_quantity, delivered_quantity,
      returned_quantity, damaged_quantity)
    VALUES (p_delivery_id, v_item_id, v_extra, 0, 0, 0)
    ON CONFLICT (delivery_id, summary_item_id) DO UPDATE
      SET loaded_quantity = public.delivery_items.loaded_quantity + EXCLUDED.loaded_quantity;
  END LOOP;

  IF NOT v_any THEN
    RAISE EXCEPTION 'enter a quantity for at least one product';
  END IF;

  SELECT COALESCE(SUM(line_total), 0) INTO v_total
    FROM public.daily_summary_items WHERE summary_id = v_delivery.summary_id;
  UPDATE public.daily_summaries
     SET total_amount = v_total, updated_at = now()
   WHERE id = v_delivery.summary_id;

  UPDATE public.deliveries SET loaded_at = now() WHERE id = p_delivery_id;
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.load_more_into_van(UUID, JSONB) TO authenticated;
