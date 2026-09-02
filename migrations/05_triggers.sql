-- migrations/05_triggers.sql
-- Trigger to update updated_at timestamps and triggers to set funding_requests.user_id and create wallets securely

CREATE OR REPLACE FUNCTION public.trigger_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END; $$;

-- funding_requests: set user_id to auth.uid() on insert if omitted
CREATE OR REPLACE FUNCTION public.funding_requests_set_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Ensure the inserting authenticated user is recorded as the owner. auth.uid() returns the caller's UID.
  IF NEW.user_id IS NULL THEN
    NEW.user_id := auth.uid();
  END IF;
  RETURN NEW;
END;
$$;

-- create wallet for new profile (idempotent)
CREATE OR REPLACE FUNCTION public.create_wallet_for_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- insert wallet with balance 0 if not exists; use ON CONFLICT to avoid duplicates
  INSERT INTO public.wallets(user_id, balance, created_at, updated_at)
  VALUES (NEW.id, 0, now(), now())
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- Attach the triggers
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_profiles') THEN
    CREATE TRIGGER set_updated_at_profiles BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_services') THEN
    CREATE TRIGGER set_updated_at_services BEFORE UPDATE ON public.services FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_account_products') THEN
    CREATE TRIGGER set_updated_at_account_products BEFORE UPDATE ON public.account_products FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_orders') THEN
    CREATE TRIGGER set_updated_at_orders BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_wallets') THEN
    CREATE TRIGGER set_updated_at_wallets BEFORE UPDATE ON public.wallets FOR EACH ROW EXECUTE FUNCTION public.trigger_set_updated_at();
  END IF;

  -- funding_requests user assignment trigger
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'funding_requests_set_user_trg') THEN
    CREATE TRIGGER funding_requests_set_user_trg BEFORE INSERT ON public.funding_requests FOR EACH ROW EXECUTE FUNCTION public.funding_requests_set_user();
  END IF;

  -- create_wallet_for_profile trigger: create wallet row when a profile is inserted
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'create_wallet_for_profile_trg') THEN
    CREATE TRIGGER create_wallet_for_profile_trg AFTER INSERT ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.create_wallet_for_profile();
  END IF;
END$$;

-- Harden trigger functions by setting search_path to public
ALTER FUNCTION public.trigger_set_updated_at() SET search_path = public;
ALTER FUNCTION public.funding_requests_set_user() SET search_path = public;
ALTER FUNCTION public.create_wallet_for_profile() SET search_path = public;
