-- migrations/06_storage_and_instructions.sql
-- Storage guidance: create a private bucket named 'payment_proofs'

-- SUPABASE ACTIONS (manual steps)
-- 1. In Supabase Dashboard -> Storage, create a new bucket named payment_proofs and keep it private.
-- 2. For admin users to view proofs, you can either:
--    a) Use Supabase Edge Functions or your own server with the SUPABASE_SERVICE_ROLE key to generate signed URLs using the Storage API, OR
--    b) Temporarily generate signed URLs in the Supabase SQL editor via a server-side process and store the short-lived URL in a separate table for admin access.

-- NOTE: Creating signed URLs requires the service_role key — do NOT include it in the frontend.

-- Recommended permissions: Keep bucket private. Only allow admin access to download using signed URLs generated server-side.

