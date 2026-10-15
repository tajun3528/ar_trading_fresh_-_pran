-- ============================================================================
-- Snacks' 22g Chanachur line packs as "poli" (a poly-pack tier between pcs
-- and carton: 8 poli/carton, 24 pcs/poli) — add it as a 5th independent unit
-- alongside pcs/jar/box/carton. Same philosophy throughout: units are
-- independent stock/price buckets, nothing auto-converts between them.
-- ============================================================================
ALTER TYPE public.unit_type ADD VALUE 'poli';
