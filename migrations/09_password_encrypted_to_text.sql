-- migrations/09_password_encrypted_to_text.sql
-- Convert account_products.password_encrypted from bytea to text (base64) so Edge Functions can store base64 ciphertext

DO $$
BEGIN
  -- only alter if the column type is bytea
  IF (SELECT data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='account_products' AND column_name='password_encrypted') = 'bytea' THEN
    ALTER TABLE public.account_products ALTER COLUMN password_encrypted TYPE text USING encode(password_encrypted, 'base64');
  END IF;
EXCEPTION WHEN undefined_table OR undefined_column THEN
  -- table/column not present yet; skip
  RAISE NOTICE 'account_products or password_encrypted column not found while attempting to alter type; skipping.';
END$$;
