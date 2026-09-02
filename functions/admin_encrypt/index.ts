// functions/admin_encrypt/index.ts
// Edge Function to allow admins to add or update account credentials securely.

import { serve } from 'std/server';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE')!;
const ENCRYPTION_KEY_BASE64 = Deno.env.get('ENCRYPTION_KEY')!;

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE, { auth: { persistSession: false } });

function uint8ArrayFromBase64(b64: string) {
  return Uint8Array.from(atob(b64), c => c.charCodeAt(0));
}

function base64FromUint8Array(arr: Uint8Array) {
  let binary = '';
  const len = arr.byteLength;
  for (let i = 0; i < len; i++) binary += String.fromCharCode(arr[i]);
  return btoa(binary);
}

async function importAesKey(base64Key: string) {
  const raw = uint8ArrayFromBase64(base64Key);
  return await crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, ['encrypt']);
}

serve(async (req) => {
  try {
    if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

    const authHeader = req.headers.get('authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '');
    if (!token) return new Response('Unauthorized', { status: 401 });

    // Verify caller
    const { data: userData, error: userErr } = await supabaseAdmin.auth.getUser(token);
    if (userErr || !userData) return new Response('Unauthorized', { status: 401 });
    const userId = userData.id;

    const { data: prof, error: profErr } = await supabaseAdmin.from('profiles').select('is_admin').eq('id', userId).single();
    if (profErr || !prof || !prof.is_admin) return new Response('Forbidden', { status: 403 });

    const body = await req.json();
    const { account_product_id, username, password_plain, price, platform, service_id } = body;
    if (!username || !password_plain) return new Response('username and password_plain required', { status: 400 });

    // encrypt password_plain using AES-GCM with random IV
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const key = await importAesKey(ENCRYPTION_KEY_BASE64);
    const encoded = new TextEncoder().encode(password_plain);
    const cipherBuf = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, encoded);
    const combined = new Uint8Array(iv.byteLength + cipherBuf.byteLength);
    combined.set(iv, 0);
    combined.set(new Uint8Array(cipherBuf), iv.byteLength);
    const blobBase64 = base64FromUint8Array(combined);

    // upsert into account_products
    if (account_product_id) {
      // update existing
      const { error: updateErr } = await supabaseAdmin.from('account_products').update({ username, password_encrypted: blobBase64, price, platform, service_id }).eq('id', account_product_id);
      if (updateErr) return new Response('DB update error', { status: 500 });
      return new Response('updated', { status: 200 });
    } else {
      const { error: insertErr } = await supabaseAdmin.from('account_products').insert([{ username, password_encrypted: blobBase64, price, platform, service_id }]);
      if (insertErr) return new Response('DB insert error', { status: 500 });
      return new Response('inserted', { status: 200 });
    }
  } catch (err) {
    console.error('admin_encrypt error', err);
    return new Response('Internal error', { status: 500 });
  }
});
