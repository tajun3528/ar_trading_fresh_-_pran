-- ============================================================================
-- Fresh's placeholder catalog (seeded with no real prices — see
-- seed-initial-catalog.sql) is being replaced with a real vendor price list
-- ("PL-G, September 2026"). The only data referencing it is early test
-- activity (3 daily_summaries from 2026-08-10, none pending), which the
-- Owner asked to fully wipe alongside the catalog rather than keep as
-- orphaned history. Delete in dependency order; Pran Chocolate is untouched
-- throughout (every statement below is scoped to Fresh's company_id).
-- ============================================================================
DO $$
DECLARE
  v_company_id UUID;
BEGIN
  SELECT id INTO v_company_id FROM public.companies WHERE name = 'Fresh';

  DELETE FROM public.delivery_items WHERE summary_item_id IN (
    SELECT dsi.id FROM public.daily_summary_items dsi
    JOIN public.products p ON p.id = dsi.product_id
    WHERE p.company_id = v_company_id
  );

  DELETE FROM public.deliveries WHERE summary_id IN (
    SELECT DISTINCT dsi.summary_id FROM public.daily_summary_items dsi
    JOIN public.products p ON p.id = dsi.product_id
    WHERE p.company_id = v_company_id
  );

  DELETE FROM public.daily_summaries WHERE id IN (
    SELECT DISTINCT dsi.summary_id FROM public.daily_summary_items dsi
    JOIN public.products p ON p.id = dsi.product_id
    WHERE p.company_id = v_company_id
  );
  -- The DELETE above cascades to daily_summary_items (ON DELETE CASCADE).

  DELETE FROM public.returns WHERE product_id IN (SELECT id FROM public.products WHERE company_id = v_company_id);
  DELETE FROM public.stock_ins WHERE product_id IN (SELECT id FROM public.products WHERE company_id = v_company_id);
  DELETE FROM public.stock WHERE product_id IN (SELECT id FROM public.products WHERE company_id = v_company_id);
  DELETE FROM public.product_price_history WHERE product_id IN (SELECT id FROM public.products WHERE company_id = v_company_id);
  DELETE FROM public.product_batches WHERE product_id IN (SELECT id FROM public.products WHERE company_id = v_company_id);
  DELETE FROM public.product_units WHERE product_id IN (SELECT id FROM public.products WHERE company_id = v_company_id);
  DELETE FROM public.products WHERE company_id = v_company_id;
  DELETE FROM public.categories WHERE company_id = v_company_id;
END $$;

-- ============================================================================
-- Fresh's real price sheet carries both a per-carton AND a per-piece figure
-- for DP/MRP (product_units already covers per-piece/per-carton TP — that's
-- the live, editable selling price), a free-text trade discount ("3PCS/CTN")
-- and standing-order tier ("16CTN/1CTN") rather than Pran Chocolate's single
-- numeric trade_qty, and an effective-margin percentage. Extend the
-- reference columns (still nullable, still just Owner-facing snapshot data)
-- rather than forking a second vendor schema.
-- ============================================================================
ALTER TABLE public.products
  ADD COLUMN mrp_price_per_pcs NUMERIC(12,2),
  ADD COLUMN trade_note TEXT,
  ADD COLUMN so_note TEXT,
  ADD COLUMN erm_percent NUMERIC(5,2);
