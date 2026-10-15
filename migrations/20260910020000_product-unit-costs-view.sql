-- ============================================================================
-- product_unit_costs — the DP cost of one unit, exposed per priced unit.
--
-- The "Set as DP" button on the salesman's monthly price screen fills from
-- this, so the figure a salesman can price at is exactly the figure profit is
-- measured against. Deriving it a second time in the app would risk the two
-- drifting apart — pricing at DP would then show a phantom profit or loss.
--
-- Only units the product is actually sold in appear. dp_price is NULL where
-- it can't be derived (e.g. a jar with no jars-per-carton set yet), which is
-- what the screen reports as "skipped" rather than filling in a wrong number.
-- ============================================================================
CREATE OR REPLACE VIEW public.product_unit_costs
WITH (security_invoker = true) AS
SELECT
  pu.product_id,
  pu.unit_type,
  pu.price                                            AS selling_price,
  public.product_unit_dp(pu.product_id, pu.unit_type) AS dp_price
FROM public.product_units pu;

GRANT SELECT ON public.product_unit_costs TO authenticated;
