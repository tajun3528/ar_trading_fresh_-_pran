-- Enums
CREATE TYPE public.user_role AS ENUM ('owner','salesman','deliveryman');
CREATE TYPE public.user_status AS ENUM ('pending','active','inactive');
CREATE TYPE public.unit_type AS ENUM ('pcs','jar','carton');
CREATE TYPE public.order_status AS ENUM ('booked','delivered','partially_delivered','cancelled');
CREATE TYPE public.return_condition AS ENUM ('good','damaged');

-- profiles: app-owned identity/role/status extending auth.users
CREATE TABLE public.profiles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  mobile TEXT NOT NULL UNIQUE,
  email TEXT,
  role public.user_role NOT NULL DEFAULT 'salesman',
  status public.user_status NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  category_id UUID NOT NULL REFERENCES public.categories(id),
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  pcs_per_jar INTEGER NOT NULL DEFAULT 1 CHECK (pcs_per_jar > 0),
  jars_per_carton INTEGER NOT NULL DEFAULT 1 CHECK (jars_per_carton > 0),
  low_stock_threshold INTEGER NOT NULL DEFAULT 0 CHECK (low_stock_threshold >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_products_category_id ON public.products(category_id);

CREATE TABLE public.product_units (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  unit_type public.unit_type NOT NULL,
  price NUMERIC(12,2) NOT NULL CHECK (price >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (product_id, unit_type)
);
CREATE INDEX idx_product_units_product_id ON public.product_units(product_id);

CREATE TABLE public.routes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  area TEXT,
  salesman_id UUID REFERENCES public.profiles(user_id),
  deliveryman_id UUID REFERENCES public.profiles(user_id),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_routes_salesman_id ON public.routes(salesman_id);
CREATE INDEX idx_routes_deliveryman_id ON public.routes(deliveryman_id);

CREATE TABLE public.shops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  owner_name TEXT,
  mobile TEXT NOT NULL,
  address TEXT NOT NULL,
  route_id UUID NOT NULL REFERENCES public.routes(id),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (name, mobile)
);
CREATE INDEX idx_shops_route_id ON public.shops(route_id);

CREATE TABLE public.stock (
  product_id UUID PRIMARY KEY REFERENCES public.products(id) ON DELETE CASCADE,
  available_pcs INTEGER NOT NULL DEFAULT 0 CHECK (available_pcs >= 0),
  damaged_pcs INTEGER NOT NULL DEFAULT 0 CHECK (damaged_pcs >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.stock_ins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES public.products(id),
  unit_type public.unit_type NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  total_pcs INTEGER NOT NULL CHECK (total_pcs > 0),
  entry_date DATE NOT NULL DEFAULT current_date,
  entered_by UUID NOT NULL REFERENCES public.profiles(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_stock_ins_product_id ON public.stock_ins(product_id);
CREATE INDEX idx_stock_ins_entry_date ON public.stock_ins(entry_date);

CREATE TABLE public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES public.shops(id),
  salesman_id UUID NOT NULL REFERENCES public.profiles(user_id),
  booking_date DATE NOT NULL DEFAULT current_date,
  delivery_date DATE NOT NULL,
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  payable_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (payable_amount >= 0),
  status public.order_status NOT NULL DEFAULT 'booked',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_orders_shop_id ON public.orders(shop_id);
CREATE INDEX idx_orders_salesman_id ON public.orders(salesman_id);
CREATE INDEX idx_orders_delivery_date ON public.orders(delivery_date);

CREATE TABLE public.order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id),
  unit_type public.unit_type NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
  line_total NUMERIC(12,2) NOT NULL CHECK (line_total >= 0)
);
CREATE INDEX idx_order_items_order_id ON public.order_items(order_id);

CREATE TABLE public.deliveries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id),
  deliveryman_id UUID NOT NULL REFERENCES public.profiles(user_id),
  delivery_datetime TIMESTAMPTZ NOT NULL DEFAULT now(),
  status public.order_status NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_deliveries_order_id ON public.deliveries(order_id);
CREATE INDEX idx_deliveries_deliveryman_id ON public.deliveries(deliveryman_id);

CREATE TABLE public.delivery_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id UUID NOT NULL REFERENCES public.deliveries(id) ON DELETE CASCADE,
  order_item_id UUID NOT NULL REFERENCES public.order_items(id),
  delivered_quantity INTEGER NOT NULL CHECK (delivered_quantity >= 0)
);
CREATE INDEX idx_delivery_items_delivery_id ON public.delivery_items(delivery_id);

CREATE TABLE public.returns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES public.shops(id),
  order_id UUID REFERENCES public.orders(id),
  product_id UUID NOT NULL REFERENCES public.products(id),
  unit_type public.unit_type NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  condition public.return_condition NOT NULL,
  reason TEXT,
  return_date DATE NOT NULL DEFAULT current_date,
  recorded_by UUID NOT NULL REFERENCES public.profiles(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_returns_shop_id ON public.returns(shop_id);
CREATE INDEX idx_returns_return_date ON public.returns(return_date);

CREATE TABLE public.payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id),
  shop_id UUID NOT NULL REFERENCES public.shops(id),
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  payment_date DATE NOT NULL DEFAULT current_date,
  collected_by UUID NOT NULL REFERENCES public.profiles(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_payments_order_id ON public.payments(order_id);
CREATE INDEX idx_payments_shop_id ON public.payments(shop_id);

-- Auto-maintain updated_at
CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();
CREATE TRIGGER categories_updated_at BEFORE UPDATE ON public.categories FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();
CREATE TRIGGER products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();
CREATE TRIGGER product_units_updated_at BEFORE UPDATE ON public.product_units FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();
CREATE TRIGGER routes_updated_at BEFORE UPDATE ON public.routes FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();
CREATE TRIGGER shops_updated_at BEFORE UPDATE ON public.shops FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();
CREATE TRIGGER stock_updated_at BEFORE UPDATE ON public.stock FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();
CREATE TRIGGER orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();

-- Every product gets a zeroed stock row automatically so RPCs never have to
-- special-case "no stock row yet".
CREATE OR REPLACE FUNCTION public.create_stock_row()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  INSERT INTO public.stock(product_id, available_pcs, damaged_pcs)
  VALUES (NEW.id, 0, 0)
  ON CONFLICT (product_id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER products_create_stock AFTER INSERT ON public.products
FOR EACH ROW EXECUTE FUNCTION public.create_stock_row();
