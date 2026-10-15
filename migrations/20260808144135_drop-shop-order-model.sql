-- The business doesn't book digital per-shop orders — salesmen deal with
-- shops on paper cash memos and only submit an aggregate daily product-total
-- for next-day delivery planning. Drop the shop/route/order/payment model
-- entirely (no real order/shop data exists yet) to make way for it.

DROP VIEW IF EXISTS public.shop_ledger_view;

DROP FUNCTION IF EXISTS public.record_payment(UUID, NUMERIC);
DROP FUNCTION IF EXISTS public.record_return(UUID, UUID, public.unit_type, INTEGER, public.return_condition, TEXT, UUID);
DROP FUNCTION IF EXISTS public.confirm_delivery(UUID, JSONB);
DROP FUNCTION IF EXISTS public.cancel_order(UUID);
DROP FUNCTION IF EXISTS public.edit_order(UUID, JSONB);
DROP FUNCTION IF EXISTS public.book_order(UUID, JSONB);

-- Tables first (CASCADE drops their RLS policies, which is what was still
-- referencing the helper functions below), then the now-unreferenced helpers.
DROP TABLE IF EXISTS public.payments CASCADE;
DROP TABLE IF EXISTS public.delivery_items CASCADE;
DROP TABLE IF EXISTS public.deliveries CASCADE;
DROP TABLE IF EXISTS public.order_items CASCADE;
DROP TABLE IF EXISTS public.orders CASCADE;
DROP TABLE IF EXISTS public.returns CASCADE;
DROP TABLE IF EXISTS public.shops CASCADE;
DROP TABLE IF EXISTS public.routes CASCADE;

DROP FUNCTION IF EXISTS public.delivery_order_id(UUID);
DROP FUNCTION IF EXISTS public.can_view_order(UUID);
DROP FUNCTION IF EXISTS public.shop_route_id(UUID);
DROP FUNCTION IF EXISTS public.is_route_deliveryman(UUID);
DROP FUNCTION IF EXISTS public.is_route_salesman(UUID);
