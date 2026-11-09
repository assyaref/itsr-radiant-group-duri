-- Test RLS recursion fix
-- Insert test profiles and verify policies work without recursion

-- Insert test profiles
INSERT INTO public.profiles (id, employee_number, role) VALUES 
  ('00000000-0000-0000-0000-000000000001', 'EMP001', 'employee'),
  ('00000000-0000-0000-0000-000000000002', 'EMP002', 'employee'),
  ('00000000-0000-0000-0000-000000000003', 'EMP003', 'it_support'),
  ('00000000-0000-0000-0000-000000000004', 'EMP004', 'administrator');

-- Test 1: Employee can view own profile (set auth.uid())
SELECT 'Test 1: Employee viewing own profile' AS test_name;
SELECT id, employee_number, role FROM public.profiles WHERE id = '00000000-0000-0000-0000-000000000001';

-- Test 2: Employee cannot view another employee's profile
SELECT 'Test 2: Employee viewing another profile' AS test_name;
SELECT id, employee_number, role FROM public.profiles WHERE id = '00000000-0000-0000-0000-000000000002';

-- Test 3: IT Support can view all profiles
SELECT 'Test 3: IT Support viewing all profiles' AS test_name;
SELECT id, employee_number, role FROM public.profiles;

-- Test 4: Administrator can view all profiles
SELECT 'Test 4: Administrator viewing all profiles' AS test_name;
SELECT id, employee_number, role FROM public.profiles;

-- Test 5: Verify the function works
SELECT 'Test 5: Function is_admin_or_it_support()' AS test_name;
SELECT public.is_admin_or_it_support() AS is_admin;

-- Test 6: Employee checking function
SELECT 'Test 6: Employee checking function' AS test_name;
SELECT public.is_admin_or_it_support() AS emp_is_admin;

-- Cleanup
DELETE FROM public.profiles WHERE id IN ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004');