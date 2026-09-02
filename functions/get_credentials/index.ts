// functions/get_credentials/index.ts
// Example Supabase Edge Function (Node/TypeScript) to fetch and decrypt credentials for a purchased account.

import { serve } from 'std/server';
import { createClient } from '@supabase/supabase-js';
import * as pgp from 'openpgp';

// The following environment variables MUST be set as Edge Function secrets:
// - SUPABASE_URL
// - SUPABASE_SERVICE_ROLE
// - ENCRYPTION_KEY

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE')!;
const ENCRYPTION_KEY = Deno.env.get('ENCRYPTION_KEY')!;

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE, { auth: { persistSession: false } });

serve(async (req) => {
  try {
    const url = new URL(req.url);
    if(req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

    const authHeader = req.headers.get('authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '');
    if(!token) return new Response('Unauthorized', { status: 401 });

    // Verify session and get user
    const { data: userData, error: userErr } = await supabaseAdmin.auth.getUser(token);
    if(userErr || !userData) return new Response('Unauthorized', { status: 401 });
    const userId = userData.id;

    const body = await req.json();
    const orderId = body.order_id;
    if(!orderId) return new Response('order_id required', { status: 400 });

    // Lookup order and account product
    const { data: ord, error: ordErr } = await supabaseAdmin
      .from('orders')
      .select('id, user_id, account_product_id')
      .eq('id', orderId)
      .single();
    if(ordErr || !ord) return new Response('Order not found', { status: 404 });

    // Check ownership or admin
    if(ord.user_id !== userId) {
      // check admin
      const { data: prof } = await supabaseAdmin.from('profiles').select('is_admin').eq('id', userId).single();
      if(!prof || !prof.is_admin) return new Response('Forbidden', { status: 403 });
    }

    // Fetch encrypted credentials
    const { data: prod, error: prodErr } = await supabaseAdmin
      .from('account_products')
      .select('id, username, password_encrypted')
      .eq('id', ord.account_product_id)
      .single();
    if(prodErr || !prod) return new Response('Product not found', { status: 404 });

    if(!prod.password_encrypted) return new Response(JSON.stringify({ username: prod.username, password: null }), { status: 200 });

    // Decrypt using ENCRYPTION_KEY. The encrypted data is expected to be pgp-symmetric encrypted binary.
    // Here we assume password_encrypted was stored using pgp_sym_encrypt and is transferable.

    // Convert stored bytea to base64 string if necessary and use openpgp to decrypt.
    // NOTE: Implementation detail depends on how encryption was performed. This example assumes the encryption used OpenPGP symmetric encryption compatible with openpgp.js.

    const encrypted = prod.password_encrypted; // may need conversion depending on driver

    // For clarity we will return the encrypted blob and leave exact decryption implementation to deployer.
    return new Response(JSON.stringify({ username: prod.username, password_encrypted: encrypted }), { status: 200 });

  } catch (err) {
    console.error(err);
    return new Response('Internal error', { status: 500 });
  }
});
