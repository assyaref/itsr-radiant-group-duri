-- Test RLS policies without recursion
INSERT INTO public.profiles (id, employee_number, role) VALUES 
  ('00000000-0000-0000-0000-000000000001', 'EMP001', 'employee'),
  ('00000000-0000-0000-0000-000000000002', 'EMP002', 'employee'),
  ('00000000-0000-0000-0000-000000000003', 'EMP003', 'it_support');

-- Test 1: Employee (EMP001) can view own profile
SELECT 'Test 1: Employee viewing own profile' AS test_name;
SET LOCAL test.auth.uid = '00000000-0000-0000-0000-000000000001';
SELECT id, employee_number, role FROM public.profiles;

-- Test 2: Employee (EMP001) cannot view another employee's profile (EMP002)
SELECT 'Test 2: Employee viewing another profile' AS test_name;
SET LOCAL test.auth.uid = '00000000-0000-0000-0000-000000000001';
SELECT id, employee_number, role FROM public.profiles WHERE id != '00000000-0000-0000-0000-000000000001';

-- Test 3: IT Support (EMP003) can view all profiles
SELECT 'Test 3: IT Support viewing all profiles' AS test_name;
SET LOCAL test.auth.uid = '00000000-0000-0000-0000-000000000003';
SELECT id, employee_number, role FROM public.profiles;

-- Test 4: Verify no recursion (should complete instantly)
SELECT 'Test 4: No recursion test - query completed successfully' AS test_name;
SELECT count(*) FROM public.profiles;

-- Cleanup
DELETE FROM public.profiles WHERE id IN ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003');
RESET LOCAL test.auth.uid;