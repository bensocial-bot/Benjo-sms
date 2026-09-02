-- migrations/01_create_schema.sql
-- Create core tables for Benjo-SMS. Safe CREATE TABLE IF NOT EXISTS statements.

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- profiles table (linked to Supabase auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text,
  full_name text,
  is_admin boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- wallets
CREATE TABLE IF NOT EXISTS public.wallets (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  balance numeric DEFAULT 0 CHECK (balance >= 0),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- wallet_transactions
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id bigserial PRIMARY KEY,
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount numeric NOT NULL,
  type text NOT NULL, -- credit|debit|refund
  reference text,
  metadata jsonb,
  created_at timestamptz DEFAULT now()
);

-- funding_requests
CREATE TABLE IF NOT EXISTS public.funding_requests (
  id bigserial PRIMARY KEY,
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  amount numeric NOT NULL,
  method text,
  reference text,
  proof_path text,
  status text DEFAULT 'pending', -- pending|approved|rejected
  processed_by uuid,
  processed_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- services
CREATE TABLE IF NOT EXISTS public.services (
  id bigserial PRIMARY KEY,
  name text NOT NULL,
  platform text,
  category text,
  description text,
  price numeric NOT NULL,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- account_products (credentials encrypted)
CREATE TABLE IF NOT EXISTS public.account_products (
  id bigserial PRIMARY KEY,
  service_id bigint REFERENCES public.services(id) ON DELETE SET NULL,
  platform text,
  username text,
  password_encrypted bytea,
  price numeric NOT NULL,
  is_sold boolean DEFAULT false,
  seller_id uuid REFERENCES public.profiles(id),
  buyer_id uuid REFERENCES public.profiles(id),
  sold_at timestamptz,
  metadata jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- orders
CREATE TABLE IF NOT EXISTS public.orders (
  id bigserial PRIMARY KEY,
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  service_id bigint REFERENCES public.services(id) ON DELETE SET NULL,
  account_product_id bigint REFERENCES public.account_products(id) ON DELETE SET NULL,
  amount numeric NOT NULL,
  status text DEFAULT 'pending', -- pending|processing|completed|cancelled|refunded
  details jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

