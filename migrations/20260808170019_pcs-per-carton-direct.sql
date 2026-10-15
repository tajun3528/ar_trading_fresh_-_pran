-- A carton's piece count isn't always a clean multiple of the jar's piece
-- count in this business (some products skip the jar tier entirely, others
-- have a carton size that doesn't divide evenly by jar size). Replace the
-- derived jars_per_carton with a directly-set pcs_per_carton, independent of
-- pcs_per_jar, matching how pcs_per_jar already works.
ALTER TABLE public.products RENAME COLUMN jars_per_carton TO pcs_per_carton;

CREATE OR REPLACE FUNCTION public.to_pieces(p_product_id UUID, p_unit public.unit_type, p_qty INTEGER)
RETURNS INTEGER
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT CASE p_unit
    WHEN 'pcs' THEN p_qty
    WHEN 'jar' THEN p_qty * pcs_per_jar
    WHEN 'carton' THEN p_qty * pcs_per_carton
  END
  FROM public.products WHERE id = p_product_id;
$$;
