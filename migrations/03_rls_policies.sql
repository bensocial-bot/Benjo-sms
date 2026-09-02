-- migrations/03_rls_policies.sql
-- Row Level Security policies - corrected syntax and tightened policies

-- Enable RLS on tables where appropriate
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.funding_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- profiles: users can insert their profile (on sign-up). Select allowed to owner or admin. Update allowed to owner only.
CREATE POLICY IF NOT EXISTS profiles_insert ON public.profiles FOR INSERT USING (auth.role() = 'authenticated') WITH CHECK (auth.uid() = id);
CREATE POLICY IF NOT EXISTS profiles_select ON public.profiles FOR SELECT USING (id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles p2 WHERE p2.id = auth.uid() AND p2.is_admin = true));
CREATE POLICY IF NOT EXISTS profiles_update ON public.profiles FOR UPDATE USING (id = auth.uid());

-- wallets: only allow owner to view; only admins (via RPCs) can update wallets directly
CREATE POLICY IF NOT EXISTS wallets_select ON public.wallets FOR SELECT USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));
CREATE POLICY IF NOT EXISTS wallets_update ON public.wallets FOR UPDATE USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));
CREATE POLICY IF NOT EXISTS wallets_insert ON public.wallets FOR INSERT USING (auth.role() = 'authenticated') WITH CHECK (user_id = auth.uid());

-- wallet_transactions: owner or admin can SELECT. INSERT restricted to admins (transactions created server-side via RPCs)
CREATE POLICY IF NOT EXISTS wallet_transactions_select ON public.wallet_transactions FOR SELECT USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));
DROP POLICY IF EXISTS wallet_transactions_insert ON public.wallet_transactions;
CREATE POLICY IF NOT EXISTS wallet_transactions_insert ON public.wallet_transactions FOR INSERT USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true)) WITH CHECK (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));

-- funding_requests: user can insert their own request (DB trigger will set user_id = auth.uid() if omitted). Users can select their requests; admins can select all. Only admins may UPDATE status.
DROP POLICY IF EXISTS funding_requests_insert ON public.funding_requests;
CREATE POLICY IF NOT EXISTS funding_requests_insert ON public.funding_requests FOR INSERT USING (auth.role() = 'authenticated') WITH CHECK (user_id = auth.uid());
CREATE POLICY IF NOT EXISTS funding_requests_select ON public.funding_requests FOR SELECT USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));
DROP POLICY IF EXISTS funding_requests_update ON public.funding_requests;
CREATE POLICY IF NOT EXISTS funding_requests_update ON public.funding_requests FOR UPDATE USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));

-- services: public can select active services; admins can manage
CREATE POLICY IF NOT EXISTS services_select ON public.services FOR SELECT USING (is_active = true OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));
CREATE POLICY IF NOT EXISTS services_insert ON public.services FOR INSERT USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));
CREATE POLICY IF NOT EXISTS services_update ON public.services FOR UPDATE USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));

-- account_products: do not reveal password_encrypted to public users. Public listing allowed only when is_sold=false AND password_encrypted IS NULL. Buyer or admin can select full record.
DROP POLICY IF EXISTS account_products_select_public ON public.account_products;
CREATE POLICY IF NOT EXISTS account_products_select_public ON public.account_products FOR SELECT USING (
  (is_sold = false AND password_encrypted IS NULL)
  OR buyer_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true)
);
DROP POLICY IF EXISTS account_products_insert ON public.account_products;
CREATE POLICY IF NOT EXISTS account_products_insert ON public.account_products FOR INSERT USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));
DROP POLICY IF EXISTS account_products_update ON public.account_products;
CREATE POLICY IF NOT EXISTS account_products_update ON public.account_products FOR UPDATE USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));

-- orders: owner or admin can see orders. Inserts must set user_id = auth.uid() (enforced by policy) or be created server-side.
DROP POLICY IF EXISTS orders_select ON public.orders;
CREATE POLICY IF NOT EXISTS orders_select ON public.orders FOR SELECT USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));
DROP POLICY IF EXISTS orders_insert ON public.orders;
CREATE POLICY IF NOT EXISTS orders_insert ON public.orders FOR INSERT USING (auth.role() = 'authenticated') WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS orders_update ON public.orders;
CREATE POLICY IF NOT EXISTS orders_update ON public.orders FOR UPDATE USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));

-- Note: critical operations (wallet updates, purchases, approvals, refunds) must be executed via RPCs (SECURITY DEFINER) and not by direct client INSERT/UPDATE.
