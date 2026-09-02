# migrations/README.md

This directory contains SQL migration files you should run in your Supabase project. Do NOT run these using the client-side ANON key.

Order to run:
1. 01_create_schema.sql
2. 02_indexes_constraints.sql
3. 03_rls_policies.sql
4. 05_triggers.sql
5. 04_functions_rpc.sql
6. 06_storage_and_instructions.sql (manual instructions)
7. 07_sample_data.sql (optional)

How to run:
- Option A: Open Supabase Dashboard -> SQL Editor, paste each file in order and run.
- Option B: Use the supabase CLI to run migrations: supabase db push or supabase migration commands.

Important notes:
- After running functions that use pgp_sym_decrypt/pgp_sym_encrypt you MUST set an encryption key in the database settings:
  SET app.encryption_key = 'your-strong-key';
  or configure via ALTER SYSTEM or environment as appropriate for your Supabase instance.

- Do NOT expose the service_role key publicly. Use server-side code or Edge Functions to generate signed storage URLs.

