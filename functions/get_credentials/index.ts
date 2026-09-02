// functions/get_credentials/index.ts
// Supabase Edge Function (Deno) to fetch and decrypt credentials for a purchased account.

import { serve } from 'std/server';
import { createClient } from '@supabase/supabase-js';

// Environment variables (Edge Function secrets):
// - SUPABASE_URL
// - SUPABASE_SERVICE_ROLE
// - ENCRYPTION_KEY (base64 encoded 16/24/32 bytes key for AES-GCM)

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE')!;
const ENCRYPTION_KEY_BASE64 = Deno.env.get('ENCRYPTION_KEY')!; // base64

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE || !ENCRYPTION_KEY_BASE64) {
  console.error('Missing required environment variables for get_credentials function');
}

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE, { auth: { persistSession: false } });

async function importAesKey(base64Key: string) {
  const raw = Uint8Array.from(atob(base64Key), c => c.charCodeAt(0));
  return await crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, ['decrypt']);
}

function base64ToUint8Array(b64: string) {
  return Uint8Array.from(atob(b64), c => c.charCodeAt(0));
}

function uint8ArrayToString(arr: Uint8Array) {
  return new TextDecoder().decode(arr);
}

serve(async (req) => {
  try {
    if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

    const authHeader = req.headers.get('authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '');
    if (!token) return new Response('Unauthorized', { status: 401 });

    // Verify user token
    const { data: userData, error: userErr } = await supabaseAdmin.auth.getUser(token);
    if (userErr || !userData) return new Response('Unauthorized', { status: 401 });
    const userId = userData.id;

    const body = await req.json();
    const orderId = body.order_id;
    if (!orderId) return new Response('order_id required', { status: 400 });

    // Lookup order and ensure caller is buyer or admin
    const { data: ord, error: ordErr } = await supabaseAdmin
      .from('orders')
      .select('id, user_id, account_product_id')
      .eq('id', orderId)
      .single();
    if (ordErr || !ord) return new Response('Order not found', { status: 404 });

    if (ord.user_id !== userId) {
      const { data: prof, error: profErr } = await supabaseAdmin
        .from('profiles')
        .select('is_admin')
        .eq('id', userId)
        .single();
      if (profErr || !prof || !prof.is_admin) return new Response('Forbidden', { status: 403 });
    }

    // Fetch encrypted credentials
    const { data: prod, error: prodErr } = await supabaseAdmin
      .from('account_products')
      .select('id, username, password_encrypted')
      .eq('id', ord.account_product_id)
      .single();
    if (prodErr || !prod) return new Response('Product not found', { status: 404 });

    if (!prod.password_encrypted) {
      return new Response(JSON.stringify({ username: prod.username, password: null }), { status: 200 });
    }

    // password_encrypted is stored as base64(iv + ciphertext)
    // decode
    const blobBase64 = prod.password_encrypted as string;
    const blob = base64ToUint8Array(blobBase64);
    // iv is first 12 bytes (96 bits) for AES-GCM
    const iv = blob.slice(0, 12);
    const ciphertext = blob.slice(12);

    // import key and decrypt
    const key = await importAesKey(ENCRYPTION_KEY_BASE64);
    const plainBuf = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, ciphertext);
    const password = uint8ArrayToString(new Uint8Array(plainBuf));

    // Return credentials to authorized caller (do NOT log plaintext)
    return new Response(JSON.stringify({ username: prod.username, password }), { status: 200 });
  } catch (err) {
    console.error('get_credentials error', err);
    return new Response('Internal error', { status: 500 });
  }
});
