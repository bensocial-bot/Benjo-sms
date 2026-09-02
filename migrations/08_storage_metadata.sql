-- migrations/08_storage_metadata.sql
-- Metadata table for payment proofs to link storage objects with owners and enforce RLS

CREATE TABLE IF NOT EXISTS public.payment_proofs (
  id bigserial PRIMARY KEY,
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  bucket text NOT NULL,
  object_path text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- RLS: only owner or admin can select/insert their payment proofs (uploads are done by client to private bucket)
ALTER TABLE public.payment_proofs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS payment_proofs_insert ON public.payment_proofs;
CREATE POLICY IF NOT EXISTS payment_proofs_insert ON public.payment_proofs FOR INSERT WITH CHECK (auth.role() = 'authenticated' AND user_id = auth.uid());

DROP POLICY IF EXISTS payment_proofs_select ON public.payment_proofs;
CREATE POLICY IF NOT EXISTS payment_proofs_select ON public.payment_proofs FOR SELECT USING (user_id = auth.uid() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));

DROP POLICY IF EXISTS payment_proofs_update ON public.payment_proofs;
CREATE POLICY IF NOT EXISTS payment_proofs_update ON public.payment_proofs FOR UPDATE USING (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_admin = true));

-- NOTE: The storage bucket itself must be created as PRIVATE via the Supabase UI or the Storage API. Admins should view proofs via signed URLs generated server-side (Edge Function) using the service role key. The payment_proofs table links uploaded objects to owners and is protected by RLS.
