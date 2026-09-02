-- migrations/02_indexes_constraints.sql
-- Indexes and constraints

-- Ensure profiles.email uniqueness if present
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles (email);

-- Indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user_id ON public.wallet_transactions (user_id);
CREATE INDEX IF NOT EXISTS idx_funding_requests_user_id ON public.funding_requests (user_id);
CREATE INDEX IF NOT EXISTS idx_account_products_sold ON public.account_products (is_sold);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON public.orders (user_id);

