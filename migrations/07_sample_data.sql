-- migrations/07_sample_data.sql
-- OPTIONAL: insert a sample admin profile (you must manually set the auth.user row or create an account and mark it admin)

-- Example: mark an existing profile as admin (replace <user-uuid>)
-- UPDATE public.profiles SET is_admin = true WHERE id = '<user-uuid>';

-- Create sample service
INSERT INTO public.services (name, platform, category, description, price) VALUES ('Sample Facebook Service', 'Facebook', 'boost', 'Sample boosting service', 1000) ON CONFLICT DO NOTHING;
