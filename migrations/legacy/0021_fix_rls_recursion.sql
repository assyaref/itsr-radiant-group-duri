-- Migration 0021: Fix RLS recursion on profiles table
-- This migration eliminates the infinite recursion caused by
-- EXISTS (SELECT 1 FROM public.profiles ...) subqueries in RLS policies
-- The solution uses a SECURITY DEFINER function to break the recursion cycle
-- Also cleanup any leftover policies from previous migrations

-- Step 0: Cleanup any leftover policies from previous migrations
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "IT Support and Admins can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Authenticated IT/Admin can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;

-- Step 1: Create a SECURITY DEFINER function that checks user role
-- This function runs with the permissions of the function owner (service_role)
-- The fully qualified name prevents search_path poisoning
CREATE OR REPLACE FUNCTION public.is_admin_or_it_support()
RETURNS BOOLEAN AS
$$
DECLARE
  v_role TEXT;
BEGIN
  -- Get the current user's role using auth.uid()
  -- The search_path is explicitly set to 'public' to prevent poisoning
  SELECT role INTO v_role
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_role IN ('it_support', 'administrator') THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public;

-- Grant execute to authenticated users only (not public)
REVOKE ALL ON FUNCTION public.is_admin_or_it_support() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin_or_it_support() TO authenticated;

-- Step 2: Update the profiles RLS policies to use the helper function
-- These policies no longer contain self-referencing subqueries,
-- which eliminates the infinite recursion

-- Policy: Employees can view their own profile
-- Allows employees to see their own profile; admins/it support see all via function check
CREATE POLICY "Employees can view own profile" ON public.profiles
  FOR SELECT USING (
    auth.uid() IS NOT NULL AND
    (auth.uid() = id OR public.is_admin_or_it_support())
  );

-- Policy: IT Support and Admins can view all profiles
-- Uses the SECURITY DEFINER function - no self-referencing subquery
CREATE POLICY "IT Support and Admins can view all profiles" ON public.profiles
  FOR SELECT USING (
    public.is_admin_or_it_support()
  );

-- Step 3: Fix ticket policies for consistency
DROP POLICY IF EXISTS "Authenticated employees can view own tickets" ON public.tickets;
DROP POLICY IF EXISTS "Authenticated IT/Admin can view all tickets" ON public.tickets;

-- Policy: Employees can view their own tickets
CREATE POLICY "Employees can view own tickets" ON public.tickets
  FOR SELECT USING (
    auth.uid() IS NOT NULL AND
    auth.uid() = reporter_id
  );

-- Policy: IT Support and Admins can view all tickets
CREATE POLICY "IT Support and Admins can view all tickets" ON public.tickets
  FOR SELECT USING (
    public.is_admin_or_it_support()
  );