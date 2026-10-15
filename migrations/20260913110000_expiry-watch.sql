-- ============================================================================
-- Expiry, for a distributor of biscuits and chocolate.
--
-- product_batches has carried batch_no/mfg_date/expiry_date since August and
-- stock_ins.batch_id can already tag a delivery to a batch, but nothing has
-- ever read them — so nobody is warned before goods go out of date, and the
-- expired stock the deliveryman collects from shops is the first anyone hears
-- of it.
--
-- What this view can honestly report is what was RECEIVED under a batch, from
-- stock_ins. It is not remaining stock: the per-unit stock buckets are not
-- tracked per batch, so full FEFO enforcement (oldest-first loading) would
-- need stock itself split by batch. Warning early is most of the value and
-- costs none of that.
--
-- Receipts are recorded per unit (5 cartons is not 5 pieces), so the quantity
-- comes back as a per-unit breakdown rather than one number that would be
-- adding cartons to pieces.
-- ============================================================================
CREATE OR REPLACE VIEW public.product_expiry_watch
WITH (security_invoker = true) AS
SELECT
  b.id                                   AS batch_id,
  b.product_id,
  p.name                                 AS product_name,
  p.company_id,
  p.category_id,
  b.batch_no,
  b.mfg_date,
  b.expiry_date,
  (b.expiry_date - current_date)         AS days_remaining,
  CASE
    WHEN b.expiry_date IS NULL              THEN 'unknown'
    WHEN b.expiry_date <  current_date      THEN 'expired'
    WHEN b.expiry_date <= current_date + 30 THEN 'critical'
    WHEN b.expiry_date <= current_date + 90 THEN 'warning'
    ELSE 'ok'
  END                                    AS status,
  si.received                            AS received,
  COALESCE(si.receipts, 0)               AS receipts,
  si.last_received_on
FROM public.product_batches b
JOIN public.products p ON p.id = b.product_id
LEFT JOIN (
  SELECT batch_id,
         string_agg(unit_qty, ', ' ORDER BY unit_qty) AS received,
         SUM(receipts)                               AS receipts,
         MAX(last_entry)                             AS last_received_on
    FROM (
      SELECT batch_id,
             SUM(quantity) || ' ' || unit_type::text AS unit_qty,
             count(*)                                AS receipts,
             MAX(entry_date)                         AS last_entry
        FROM public.stock_ins
       WHERE batch_id IS NOT NULL
       GROUP BY batch_id, unit_type
    ) per_unit
   GROUP BY batch_id
) si ON si.batch_id = b.id;

GRANT SELECT ON public.product_expiry_watch TO authenticated;
