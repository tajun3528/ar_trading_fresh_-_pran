-- ============================================================================
-- Some products are packed in an intermediate "box" tier between pieces and
-- cartons (e.g. 24 pcs/box, 4 boxes/carton) — add it as a 4th independent
-- unit alongside pcs/jar/carton. Same philosophy as the rest of this app's
-- stock model: units are independent stock/price buckets, nothing
-- auto-converts between them.
-- ============================================================================
ALTER TYPE public.unit_type ADD VALUE 'box';
