-- ============================================================================
-- A salesman opening the order page for a month they haven't priced saw the
-- catalog trade price on every line, flagged as a fallback. The price was
-- right, but it was never theirs — nothing was stored, so profit had no
-- selling price to measure against and the line showed as "priced at TP".
--
-- This fills the gaps for a month from the catalog price, once, leaving
-- anything already priced alone. The salesman then has a real monthly price
-- on every line, which they can edit on the Monthly prices page.
--
-- The catalog price is the right seed: for Fresh it is the trade price, and
-- for Pran it is the box price the Owner set, falling back to the After Trade
-- TP where none was given.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ensure_monthly_prices(p_month DATE)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_month DATE;
  v_company_id UUID;
  v_count INTEGER;
BEGIN
  IF public.current_role() IS DISTINCT FROM 'salesman' OR public.current_status() IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'only an active salesman has monthly selling prices';
  END IF;
  v_company_id := public.current_company_id();
  IF v_company_id IS NULL THEN
    RETURN 0;
  END IF;

  v_month := date_trunc('month', COALESCE(p_month, current_date))::date;

  INSERT INTO public.salesman_monthly_prices (salesman_id, product_id, unit_type, month, selling_price)
  SELECT auth.uid(), pu.product_id, pu.unit_type, v_month, pu.price
    FROM public.product_units pu
    JOIN public.products p ON p.id = pu.product_id
   WHERE p.company_id = v_company_id
     AND p.is_active
     AND pu.price > 0
  ON CONFLICT (salesman_id, product_id, unit_type, month) DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ensure_monthly_prices(DATE) TO authenticated;
