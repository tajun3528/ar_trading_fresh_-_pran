-- ============================================================================
-- A deliveryman could read the products on an order but not their categories.
--
-- categories_select only admitted the Owner or a caller whose own company
-- matched, and a deliveryman belongs to no company — so the query returned an
-- empty list and the delivery page, which groups the round by category, drew
-- nothing at all. The returns and damage inputs were there; there were simply
-- no category sections to hang them under.
--
-- products_select already carries the carve-out this needs: anything sitting
-- on a summary the caller is allowed to see is visible to them. Categories
-- now follow the same rule.
-- ============================================================================
DROP POLICY IF EXISTS categories_select ON public.categories;

CREATE POLICY categories_select ON public.categories
  FOR SELECT TO authenticated
  USING (
    public.current_role() = 'owner'
    OR company_id = public.current_company_id()
    OR EXISTS (
      SELECT 1
        FROM public.products p
        JOIN public.daily_summary_items dsi ON dsi.product_id = p.id
       WHERE p.category_id = categories.id
         AND public.can_view_summary(dsi.summary_id)
    )
  );
