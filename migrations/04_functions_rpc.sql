-- migrations/04_functions_rpc.sql
-- Server-side functions (RPCs) to perform sensitive operations. All use auth.uid() to identify caller.

-- 1) credit_wallet_rpc(target_user UUID, amt NUMERIC, note TEXT)
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

-- 2) approve_funding_rpc(fid bigint, approve boolean)
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

  -- IMPORTANT: Do NOT decrypt credentials here. Decryption is moved to a protected Edge Function that holds the encryption secret.

  RETURN jsonb_build_object('status','ok','order_id',order_id);
END; $$;

-- 4) refund_wallet_rpc(order_id bigint, reason text)
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

-- Harden SECURITY DEFINER functions by setting search_path = public
ALTER FUNCTION public.credit_wallet_rpc(uuid, numeric, text) SET search_path = public;
ALTER FUNCTION public.approve_funding_rpc(bigint, boolean) SET search_path = public;
ALTER FUNCTION public.purchase_account_rpc(bigint) SET search_path = public;
ALTER FUNCTION public.refund_wallet_rpc(bigint, text) SET search_path = public;

-- NOTE: Decryption of credentials has been moved to a secure Edge Function. See functions/get_credentials/README.md for deployment & configuration instructions.
