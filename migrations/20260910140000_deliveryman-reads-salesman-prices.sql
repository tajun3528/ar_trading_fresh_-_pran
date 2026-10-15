-- ============================================================================
-- The damage page has to show the deliveryman what the refund comes to as he
-- types, and that is valued at the salesman's own monthly selling price. The
-- policy admitted only the Owner and the salesman themselves, so a paired
-- deliveryman could not read the very figure his cash total depends on.
--
-- Widened to the deliveryman paired with that salesman — the same pairing
-- that already decides whose orders he is allowed to deliver at all.
-- ============================================================================
DROP POLICY IF EXISTS salesman_monthly_prices_select ON public.salesman_monthly_prices;

CREATE POLICY salesman_monthly_prices_select ON public.salesman_monthly_prices
  FOR SELECT TO authenticated
  USING (
    public.current_role() = 'owner'
    OR salesman_id = auth.uid()
    OR public.is_paired_deliveryman(salesman_id)
  );
