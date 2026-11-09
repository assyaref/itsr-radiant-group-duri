-- Migration 0020: Critical Security Fixes - Login Security & RLS Hardening
-- DBA Review Required Before Application to Production
-- This migration addresses:
-- 1. Pre-login employee number enumeration vulnerability
-- 2. Adds login_attempts table for rate limiting
-- 3. Fixes RLS policies to block unauthenticated access
-- 4. Fixes trigger security issues from migration 0019
-- 5. Adds SECURITY DEFINER hardening with proper search_path

BEGIN;

-- 1. Create login_attempts table for rate limiting (only accessible by service role)
CREATE TABLE public.login_attempts (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  ip_address TEXT NOT NULL,
  employee_number TEXT,
  user_id UUID REFERENCES public.profiles(id),
  success BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Enable RLS and create policy that only blocks all user access (service role bypasses RLS)
ALTER TABLE public.login_attempts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "No direct user access to login_attempts" ON public.login_attempts
  FOR ALL USING (false);

-- 2. Fix profiles RLS to PREVENT unauthenticated access
-- Existing policies only checked if auth.uid() = id, but didn't block null auth.uid()
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Authenticated users can view own profile" ON public.profiles
  FOR SELECT USING (auth.uid() IS NOT NULL AND auth.uid() = id);

DROP POLICY IF EXISTS "IT Support and Admins can view all profiles" ON public.profiles;
CREATE POLICY "Authenticated IT/Admin can view all profiles" ON public.profiles
  FOR SELECT USING (
    auth.uid() IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role IN ('it_support', 'administrator')
    )
  );

-- 3. Fix all other tables to block unauthenticated access
-- Tickets RLS hardening
DROP POLICY IF EXISTS "Employees can view own tickets" ON public.tickets;
CREATE POLICY "Authenticated employees can view own tickets" ON public.tickets
  FOR SELECT USING (auth.uid() IS NOT NULL AND auth.uid() = reporter_id);

DROP POLICY IF EXISTS "IT Support and Admins can view all tickets" ON public.tickets;
CREATE POLICY "Authenticated IT/Admin can view all tickets" ON public.tickets
  FOR SELECT USING (
    auth.uid() IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role IN ('it_support', 'administrator')
    )
  );

-- 4. Fix trigger functions from migration 0019 to set proper search_path
-- This prevents search_path poisoning attacks on SECURITY DEFINER functions
CREATE OR REPLACE FUNCTION public.log_ticket_status_change()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO public.ticket_activity_log (
      ticket_id, 
      actor_id, 
      action, 
      old_value, 
      new_value, 
      created_at
    ) VALUES (
      NEW.id, 
      auth.uid(), 
      'status_changed', 
      OLD.status, 
      NEW.status, 
      NOW()
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public;  -- Explicit search_path prevents poisoning

CREATE OR REPLACE FUNCTION public.log_ticket_assignment_change()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.assigned_to_id IS NULL AND NEW.assigned_to_id IS NOT NULL THEN
    INSERT INTO public.ticket_activity_log (
      ticket_id, 
      actor_id, 
      action, 
      new_value, 
      created_at
    ) VALUES (
      NEW.id, 
      auth.uid(), 
      'assigned', 
      NEW.assigned_to_id::text, 
      NOW()
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public;  -- Explicit search_path prevents poisoning

-- 5. Grant execute permissions only to needed roles
REVOKE ALL ON FUNCTION public.log_ticket_status_change() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_ticket_status_change() TO authenticated;
REVOKE ALL ON FUNCTION public.log_ticket_assignment_change() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_ticket_assignment_change() TO authenticated;

-- 6. Fix ticket_activity_log RLS to block unauthenticated access
DROP POLICY IF EXISTS "Employees can view activity logs for own tickets" ON public.ticket_activity_log;
CREATE POLICY "Authenticated employees can view activity logs for own tickets" ON public.ticket_activity_log
  FOR SELECT USING (
    auth.uid() IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM public.tickets
      WHERE id = ticket_id AND reporter_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "IT Support and Admins can view all activity logs" ON public.ticket_activity_log;
CREATE POLICY "Authenticated IT/Admin can view all activity logs" ON public.ticket_activity_log
  FOR SELECT USING (
    auth.uid() IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role IN ('it_support', 'administrator')
    )
  );

-- 7. Verify and fix ticket_comments RLS to block unauthenticated access
DROP POLICY IF EXISTS "Employees can view comments on their own tickets" ON public.ticket_comments;
CREATE POLICY "Authenticated employees can view public comments on own tickets" ON public.ticket_comments
  FOR SELECT USING (
    auth.uid() IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM public.tickets
      WHERE id = ticket_id AND reporter_id = auth.uid()
    ) AND is_internal = false
  );

-- 8. Add atomic rate limiting function with proper locking
-- This prevents race conditions from parallel requests
-- Uses pg_advisory_xact_lock to ensure check-and-insert is atomic
CREATE OR REPLACE FUNCTION public.check_rate_limit(
  p_ip_address TEXT,
  p_max_attempts INTEGER,
  p_window_minutes INTEGER
) RETURNS BOOLEAN AS $$
DECLARE
  v_lock_id BIGINT;
  v_attempt_count INTEGER;
BEGIN
  -- Use advisory lock based on IP to prevent race conditions
  -- This ensures check-and-insert are atomic across concurrent requests
  SELECT ('x'||substr(md5(p_ip_address), 1, 16))::bit(64)::bigint INTO v_lock_id;
  PERFORM pg_advisory_xact_lock(v_lock_id);

  -- Clean up old attempts within the transaction
  DELETE FROM public.login_attempts
  WHERE ip_address = p_ip_address
    AND created_at < NOW() - (p_window_minutes || ' minutes')::INTERVAL;

  -- Count remaining attempts after cleanup
  SELECT COUNT(*) INTO v_attempt_count
  FROM public.login_attempts
  WHERE ip_address = p_ip_address;

  -- If at or above limit, fail-closed: block the request
  IF v_attempt_count >= p_max_attempts THEN
    RETURN false;
  END IF;

  -- Insert the new attempt within the same locked transaction
  INSERT INTO public.login_attempts (ip_address, employee_number, success, created_at)
  VALUES (p_ip_address, NULL, false, NOW());

  RETURN true;
EXCEPTION
  WHEN OTHERS THEN
    -- Fail-closed: if any database error occurs, block the request
    RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public;

-- Secure the rate limiting function
REVOKE ALL ON FUNCTION public.check_rate_limit(TEXT, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(TEXT, INTEGER, INTEGER) TO service_role;

-- 9. Add retention policy for login_attempts (auto-cleanup of old records)
-- Create a function to cleanup old login attempts
CREATE OR REPLACE FUNCTION public.cleanup_old_login_attempts()
RETURNS INTEGER AS $$
DECLARE
  v_deleted_count INTEGER;
BEGIN
  DELETE FROM public.login_attempts
  WHERE created_at < NOW() - INTERVAL '7 days'; -- Keep only 7 days of history
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RETURN v_deleted_count;
EXCEPTION
  WHEN OTHERS THEN
    RETURN 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public;

REVOKE ALL ON FUNCTION public.cleanup_old_login_attempts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cleanup_old_login_attempts() TO service_role;

COMMIT;

-- Post-migration notes:
-- 1. This migration MUST be applied before enabling the login edge function
-- 2. Edge function requires the following environment variables:
--    - SUPABASE_URL
--    - SUPABASE_SERVICE_ROLE_KEY (only available to the edge function runtime)
-- 3. The edge function must be deployed with proper CORS configuration
-- 4. Verify that all tables have RLS enabled after applying this migration
-- 5. Run the staging RLS tests to verify all security policies work correctly