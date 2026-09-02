-- migrations/05_triggers.sql
-- Trigger to update updated_at timestamps

CREATE OR REPLACE FUNCTION public.trigger_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END; $$;

-- Attach the trigger to tables that have updated_at
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
END$$;
