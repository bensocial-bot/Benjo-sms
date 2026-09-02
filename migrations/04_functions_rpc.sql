-- migrations/04_functions_rpc.sql
-- Server-side functions (RPCs) to perform sensitive operations. All use auth.uid() to identify caller.

-- 1) credit_wallet_rpc(user_id UUID, amount NUMERIC, note TEXT)
-- Credits a user's wallet and creates a wallet_transaction. This function should be SECURITY DEFINER and restricted to admins or called from another admin-only function.

CREATE OR REPLACE FUNCTION public.credit_wallet_rpc(
  target_user uuid,
  amt numeric,
  note text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  caller uuid := auth.uid();
BEGIN
  -- check caller is admin
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = caller AND p.is_admin = true) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF amt <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  -- create wallet row if missing
  INSERT INTO public.wallets(user_id, balance) SELECT target_user, 0 WHERE NOT EXISTS (SELECT 1 FROM public.wallets w WHERE w.user_id = target_user);

  -- update wallet
  UPDATE public.wallets SET balance = balance + amt, updated_at = now() WHERE user_id = target_user;

  -- insert transaction
  INSERT INTO public.wallet_transactions(user_id, amount, type, reference, metadata)
  VALUES (target_user, amt, 'credit', note, jsonb_build_object('processed_by', caller));

  RETURN jsonb_build_object('status','ok');
END; $$;

-- 2) approve_funding_rpc(funding_request_id bigint, approve boolean)
-- Admin approves/rejects funding. On approve => credit user's wallet via credit_wallet_rpc and mark funding request approved. Uses auth.uid() as admin.

CREATE OR REPLACE FUNCTION public.approve_funding_rpc(fid bigint, approve boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  caller uuid := auth.uid();
  fr record;
BEGIN
  -- verify admin
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = caller AND p.is_admin = true) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  SELECT * INTO fr FROM public.funding_requests WHERE id = fid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'funding_request_not_found';
  END IF;

  IF fr.status = 'approved' THEN
    RAISE EXCEPTION 'already_approved';
  END IF;

  IF approve THEN
    -- credit wallet
    PERFORM public.credit_wallet_rpc(fr.user_id, fr.amount, 'funding_approval:' || fid::text);
    UPDATE public.funding_requests SET status = 'approved', processed_by = caller, processed_at = now() WHERE id = fid;
  ELSE
    UPDATE public.funding_requests SET status = 'rejected', processed_by = caller, processed_at = now() WHERE id = fid;
  END IF;

  RETURN jsonb_build_object('status','ok');
END; $$;

-- 3) purchase_account_rpc(account_product_id bigint)
-- Atomic purchase: uses auth.uid() as buyer, checks wallet balance, checks availability, deducts wallet, creates order, marks account sold, assigns buyer, inserts wallet transaction. Returns order and decrypted credentials.

CREATE OR REPLACE FUNCTION public.purchase_account_rpc(account_product_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  buyer uuid := auth.uid();
  prod record;
  buyer_wallet record;
  order_id bigint;
  decrypted_credentials text;
BEGIN
  IF buyer IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- lock the product row
  SELECT * INTO prod FROM public.account_products WHERE id = account_product_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'product_not_found';
  END IF;

  IF prod.is_sold THEN
    RAISE EXCEPTION 'product_already_sold';
  END IF;

  -- get buyer wallet
  SELECT * INTO buyer_wallet FROM public.wallets WHERE user_id = buyer FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_wallet';
  END IF;

  IF buyer_wallet.balance < prod.price THEN
    RAISE EXCEPTION 'insufficient_funds';
  END IF;

  -- deduct wallet
  UPDATE public.wallets SET balance = balance - prod.price, updated_at = now() WHERE user_id = buyer;
  INSERT INTO public.wallet_transactions(user_id, amount, type, reference, metadata) VALUES (buyer, prod.price, 'debit', 'purchase_account:'||account_product_id::text, jsonb_build_object('account_product_id', account_product_id));

  -- create order
  INSERT INTO public.orders(user_id, service_id, account_product_id, amount, status, created_at)
  VALUES (buyer, prod.service_id, prod.id, prod.price, 'completed', now()) RETURNING id INTO order_id;

  -- mark account sold
  UPDATE public.account_products SET is_sold = true, buyer_id = buyer, sold_at = now() WHERE id = account_product_id;

  -- attempt to decrypt credentials if password_encrypted present. Requires pgp_sym_decrypt and an encryption key stored in a config var 'app.encryption_key'.
  IF prod.password_encrypted IS NOT NULL THEN
    BEGIN
      decrypted_credentials := pgp_sym_decrypt(prod.password_encrypted, current_setting('app.encryption_key'));
    EXCEPTION WHEN OTHERS THEN
      decrypted_credentials := null;
    END;
  END IF;

  RETURN jsonb_build_object('status','ok','order_id',order_id,'credentials', decrypted_credentials);
END; $$;

-- 4) refund_wallet_rpc(order_id bigint, reason text)
-- Admin refunds order amount back to user if not already refunded
CREATE OR REPLACE FUNCTION public.refund_wallet_rpc(order_id_param bigint, reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  caller uuid := auth.uid();
  ord record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = caller AND p.is_admin = true) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  SELECT * INTO ord FROM public.orders WHERE id = order_id_param FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  IF ord.status = 'refunded' THEN RAISE EXCEPTION 'already_refunded'; END IF;

  -- credit wallet
  PERFORM public.credit_wallet_rpc(ord.user_id, ord.amount, 'refund_order:'||order_id_param::text);

  -- mark order refunded
  UPDATE public.orders SET status = 'refunded', updated_at = now() WHERE id = order_id_param;

  RETURN jsonb_build_object('status','ok');
END; $$;

-- NOTE: SECURITY CONSIDERATIONS
-- These functions are SECURITY DEFINER and rely on current_setting('app.encryption_key') being set for encryption/decryption.
-- Keep the encryption key safe (do not store it in frontend). You can set it via Supabase SQL editor or environment for the database.

