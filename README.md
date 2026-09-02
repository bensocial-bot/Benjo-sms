# README.md

# Benjo-SMS (Supabase Integration)

This branch (supabase-integration) contains a secure, deployable implementation of the Benjo-SMS marketplace using Supabase.

IMPORTANT: Do NOT commit secrets. Use Supabase Edge Function secrets for sensitive values.

## Overview
- Frontend: static site (index.html + js/app.js). Compatible with GitHub Pages.
- Backend: Supabase (Postgres + Auth + Storage + Edge Functions)
- Edge Functions: credential management and signed URL generation
- RLS: row-level security enforced for all sensitive tables
- Wallets, funding, orders, account marketplace implemented with secure RPCs and triggers

## Migration & Deployment Order
1. migrations/01_create_schema.sql
2. migrations/02_indexes_constraints.sql
3. migrations/03_rls_policies.sql
4. migrations/05_triggers.sql
5. migrations/04_functions_rpc.sql
6. migrations/09_password_encrypted_to_text.sql
7. migrations/08_storage_metadata.sql
8. migrations/06_storage_and_instructions.sql (manual bucket creation)
9. migrations/07_sample_data.sql (optional)

Run migrations in this order using the Supabase SQL editor or supabase CLI.

## Required One-time Dashboard/API Setup
- Create Storage bucket `payment_proofs` and set it to private (Dashboard or Storage API using service-role key).
- Configure Supabase Edge Function secrets (see below).

## Edge Functions (must be deployed)
- get_credentials: returns decrypted credentials to authorized buyer or admin
- admin_encrypt: admin-only function to encrypt and store credentials
- get_signed_url: returns signed URL for private payment proof viewing

## Edge Function Secrets (set via Supabase dashboard or CLI)
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE
- ENCRYPTION_KEY (base64, 16/24/32 bytes)

## Frontend Configuration
- index.html expects the following meta tags to be set (replace values at deploy time):
  - <meta name="supabase-url" content="https://your-project.supabase.co">
  - <meta name="supabase-anon-key" content="YOUR_ANON_KEY">

Only the anon key may be present in the frontend. Never commit service-role key or ENCRYPTION_KEY.

## Admin workflow (secure credential entry)
- Use admin panel to send plaintext credentials to the `admin_encrypt` Edge Function (over HTTPS) with Bearer token.
- The Edge Function encrypts the credentials with ENCRYPTION_KEY and stores them in the DB.

## Credential retrieval
- After purchase, frontend calls the `get_credentials` Edge Function (via supabaseClient.functions.invoke or fetch) with the buyer's access token.
- The Edge Function verifies buyer or admin, fetches encrypted blob, decrypts with ENCRYPTION_KEY, and returns credentials.

## Storage & Proofs
- The `payment_proofs` bucket must be private. Uploads happen from the browser using anon key to the private bucket, and metadata is recorded in `payment_proofs` table.
- To view proofs, admins or owners request signed URLs via `get_signed_url` Edge Function which uses the service-role key to generate short-lived URLs.

## Security Notes
- All sensitive operations (wallet credits, purchases, refunds) are implemented as SECURITY DEFINER RPCs and validate auth.uid() server-side.
- RLS prevents unauthorized reads/writes. Admin checks always use profiles.is_admin in DB.
- No secrets are stored in the repo.

## Testing checklist
- Run migrations in order above
- Create private bucket `payment_proofs`
- Deploy Edge Functions and set secrets
- Create an admin user (set profiles.is_admin = true for that user via SQL)
- Test flows: sign-up, funding request, proof upload, admin approval, purchase, credential retrieval

