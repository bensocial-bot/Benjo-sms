# functions/get_credentials/README.md

This Edge Function decrypts account credentials and returns them only to the buyer or to an admin.

Security model:
- The function runs server-side and holds two secrets:
  - SUPABASE_URL
  - SUPABASE_SERVICE_ROLE (service role key; store as Edge function secret)
  - ENCRYPTION_KEY (symmetric key used with pgp_sym_encrypt/pgp_sym_decrypt; store as Edge function secret)

Behavior:
1. Caller (frontend) calls the Edge Function endpoint with an Authorization header: Bearer <access_token> (user's access token).
2. The Edge Function verifies the token by calling the Supabase Auth API (using the service role key) or by decoding the JWT.
3. The Edge Function looks up the order in the database using the service role key and confirms the caller is the order.user_id (buyer) or is an admin.
4. The Edge Function fetches the account_products.password_encrypted for the relevant account_product_id and uses ENCRYPTION_KEY to decrypt it (pgp_sym_decrypt in Node via openpgp or using Postgres pgp_sym_decrypt by running a secure query).
5. The Edge Function returns the decrypted credentials to the caller.

Deployment steps:
- Create an Edge Function at functions/get_credentials (code sample provided in index.ts).
- Set Edge Function secrets:
  - SUPABASE_URL (https://your-project.supabase.co)
  - SUPABASE_SERVICE_ROLE (from Supabase project settings)
  - ENCRYPTION_KEY (the symmetric key used to encrypt credentials)

DO NOT expose SUPABASE_SERVICE_ROLE or ENCRYPTION_KEY to the browser or commit them to source control.
