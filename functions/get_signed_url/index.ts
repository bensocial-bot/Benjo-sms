// functions/get_signed_url/index.ts
// Edge Function to generate short-lived signed URLs for private storage objects. Admins or owners may request a signed URL.

import { serve } from 'std/server';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE')!;

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE, { auth: { persistSession: false } });

serve(async (req) => {
  try {
    if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

    const authHeader = req.headers.get('authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '');
    if (!token) return new Response('Unauthorized', { status: 401 });

    // Verify user
    const { data: userData, error: userErr } = await supabaseAdmin.auth.getUser(token);
    if (userErr || !userData) return new Response('Unauthorized', { status: 401 });
    const userId = userData.id;

    const body = await req.json();
    const { proof_id, expires_sec } = body;
    if (!proof_id) return new Response('proof_id required', { status: 400 });

    // lookup payment_proofs row and verify ownership or admin
    const { data: proof, error: proofErr } = await supabaseAdmin.from('payment_proofs').select('id, user_id, bucket, object_path').eq('id', proof_id).single();
    if (proofErr || !proof) return new Response('Proof not found', { status: 404 });

    if (proof.user_id !== userId) {
      const { data: prof } = await supabaseAdmin.from('profiles').select('is_admin').eq('id', userId).single();
      if(!prof || !prof.is_admin) return new Response('Forbidden', { status: 403 });
    }

    const bucket = proof.bucket || 'payment_proofs';
    const objectPath = proof.object_path;
    const expires = Number(expires_sec) || 60; // default 60 seconds

    const { data: urlData, error: urlErr } = await supabaseAdmin.storage.from(bucket).createSignedUrl(objectPath, expires);
    if (urlErr || !urlData) return new Response('Failed to create signed URL', { status: 500 });

    return new Response(JSON.stringify({ url: urlData.signedURL }), { status: 200 });
  } catch (err) {
    console.error('get_signed_url error', err);
    return new Response('Internal error', { status: 500 });
  }
});
