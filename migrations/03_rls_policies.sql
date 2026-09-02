-- migrations/03_rls_policies.sql
-- Row Level Security policies

-- Enable RLS on tables where appropriate
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.funding_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Helper policy: allow authenticated users to insert their profile row (on signup)
CREATE POLICY IF NOT EXISTS profiles_insert ON public.profiles FOR INSERT USING (auth.role() = 'authenticated') WITH CHECK (auth.uid() = id);
CREATE POLICY IF NOT EXISTS profiles_select ON public.profiles FOR SELECT USING (id = auth.uid() OR exists (select 1 from public.profiles p2 where p2.id = auth.uid() and p2.is_admin = true));
CREATE POLICY IF NOT EXISTS profiles_update ON public.profiles FOR UPDATE USING (id = auth.uid());

-- wallets: only allow owner to view and insert (server may create wallet rows)
CREATE POLICY IF NOT EXISTS wallets_select ON public.wallets FOR SELECT USING (user_id = auth.uid() OR exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
CREATE POLICY IF NOT EXISTS wallets_update ON public.wallets FOR UPDATE USING (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
CREATE POLICY IF NOT EXISTS wallets_insert ON public.wallets FOR INSERT USING (auth.role() = 'authenticated') WITH CHECK (user_id = auth.uid());

-- wallet_transactions: owner can insert (server/RPC will insert), owner can select their transactions
CREATE POLICY IF NOT EXISTS wallet_transactions_select ON public.wallet_transactions FOR SELECT USING (user_id = auth.uid() OR exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
CREATE POLICY IF NOT EXISTS wallet_transactions_insert ON public.wallet_transactions FOR INSERT USING (auth.role() = 'authenticated') WITH CHECK (user_id = auth.uid() OR exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));

-- funding_requests: user can insert their own request, user can view their requests; admins can view all
CREATE POLICY IF NOT EXISTS funding_requests_insert ON public.funding_requests FOR INSERT USING (auth.role() = 'authenticated') WITH CHECK (user_id = auth.uid());
CREATE POLICY IF NOT EXISTS funding_requests_select ON public.funding_requests FOR SELECT USING (user_id = auth.uid() OR exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
CREATE POLICY IF NOT EXISTS funding_requests_update ON public.funding_requests FOR UPDATE USING (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));

-- services: public can select active services
CREATE POLICY IF NOT EXISTS services_select ON public.services FOR SELECT USING (is_active = true OR exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
CREATE POLICY IF NOT EXISTS services_insert ON public.services FOR INSERT USING (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
CREATE POLICY IF NOT EXISTS services_update ON public.services FOR UPDATE USING (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));

-- account_products: do not reveal credentials unless buyer or admin. Allow listing available products (is_sold = false) to public
CREATE POLICY IF NOT EXISTS account_products_select_public ON public.account_products FOR SELECT USING (is_sold = false OR buyer_id = auth.uid() OR exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
CREATE POLICY IF NOT_EXISTS account_products_insert ON public.account_products FOR INSERT USING (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
CREATE POLICY IF NOT EXISTS account_products_update ON public.account_products FOR UPDATE USING (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));

-- orders: owner or admin can see orders
CREATE POLICY IF NOT EXISTS orders_select ON public.orders FOR SELECT USING (user_id = auth.uid() OR exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
CREATE POLICY IF NOT_EXISTS orders_insert ON public.orders FOR INSERT USING (auth.role() = 'authenticated') WITH CHECK (user_id = auth.uid());
CREATE POLICY IF NOT EXISTS orders_update ON public.orders FOR UPDATE USING (user_id = auth.uid() OR exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));

-- Note: many operations (wallet updates, purchases, approvals) should be done via RPC functions with SECURITY DEFINER and NOT by direct table updates from the client.

