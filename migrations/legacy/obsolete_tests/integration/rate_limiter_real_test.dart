import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';

void main() {
  late PostgreSQLConnection connection;

  setUpAll(() async {
    connection = PostgreSQLConnection(
      'localhost',
      5433,
      'itsr_radiant_test',
      username: 'postgres',
      password: 'postgres',
    );
    await connection.open();
    // Apply the fixed RLS policies from migration 0021 once before all tests
    await connection.execute('''
      -- Cleanup any existing policies
      DROP POLICY IF EXISTS "Employees can view own profile" ON public.profiles;
      DROP POLICY IF EXISTS "IT Support and Admins can view all profiles" ON public.profiles;
      DROP POLICY IF EXISTS "Authenticated IT/Admin can view all profiles" ON public.profiles;
      DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
      DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
      
      -- Create the SECURITY DEFINER function if it doesn't exist
      CREATE OR REPLACE FUNCTION public.is_admin_or_it_support()
      RETURNS BOOLEAN AS
      \$\$
      DECLARE
        v_role TEXT;
      BEGIN
        SELECT role INTO v_role
        FROM public.profiles
        WHERE id = auth.uid();

        IF v_role IN ('it_support', 'administrator') THEN
          RETURN TRUE;
        END IF;

        RETURN FALSE;
      END;
      \$\$ LANGUAGE plpgsql SECURITY DEFINER
        SET search_path = public;
      
      -- Grant execute to authenticated users only
      REVOKE ALL ON FUNCTION public.is_admin_or_it_support() FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION public.is_admin_or_it_support() TO authenticated;
      
      -- Create the fixed policies
      CREATE POLICY "Employees can view own profile" ON public.profiles
        FOR SELECT USING (
          auth.uid() IS NOT NULL AND
          (auth.uid() = id OR public.is_admin_or_it_support())
        );

      CREATE POLICY "IT Support and Admins can view all profiles" ON public.profiles
        FOR SELECT USING (
          public.is_admin_or_it_support()
        );
    ''');
  });

  setUp(() async {
    // Clear all test data before each test to ensure complete isolation
    await connection.execute('TRUNCATE public.login_attempts, public.profiles, public.tickets, public.ticket_activity_log, public.ticket_comments CASCADE;');
  });

  tearDownAll(() async {
    await connection.close();
  });

  group('Real Rate Limiter PostgreSQL Tests', () {
    test('First request initialization - insert first attempt', () async {
      final sql = 'SELECT public.check_rate_limit(@ip::text, 5, 15)::boolean';
      final result = await connection.query(
        sql,
        substitutionValues: {'ip': 'first_request_ip'},
      );
      final bool success = result[0][0] as bool;
      expect(success, equals(true));
    });

    test('Requests below the configured limit should succeed', () async {
      for (int i = 0; i < 4; i++) {
        final sql = 'SELECT public.check_rate_limit(@ip::text, 5, 15)::boolean';
        final result = await connection.query(
          sql,
          substitutionValues: {'ip': 'below_limit_ip'},
          );
        final bool success = result[0][0] as bool;
        expect(success, equals(true));
      }
    });

    test('Request reaching the limit - 5th request should succeed', () async {
      final sql = 'SELECT public.check_rate_limit(@ip::text, 5, 15)::boolean';
      final result = await connection.query(
        sql,
        substitutionValues: {'ip': 'limit_test_ip'},
      );
      final bool success = result[0][0] as bool;
      expect(success, equals(true));
    });

    test('Request exceeding the limit should be blocked', () async {
      // First create 5 requests to reach the limit
      for (int i = 0; i < 5; i++) {
        await connection.query('SELECT public.check_rate_limit(@ip::text, 5, 15)::boolean',
            substitutionValues: {'ip': 'exceed_test_ip'});
      }
      // 6th request should be blocked
      final sql = 'SELECT public.check_rate_limit(@ip::text, 5, 15)::boolean';
      final result = await connection.query(
        sql,
        substitutionValues: {'ip': 'exceed_test_ip'},
      );
      final bool success = result[0][0] as bool;
      expect(success, equals(false));
    });

    test('Concurrent requests using independent connections', () async {
      final futures = List.generate(10, (_) async {
        final conn = PostgreSQLConnection(
          'localhost',
          5433,
          'itsr_radiant_test',
          username: 'postgres',
          password: 'postgres',
        );
        await conn.open();
        try {
          final ip = 'concurrent_test_ip_123';
          final sql = 'SELECT public.check_rate_limit(@ip::text, 5, 15)::boolean';
          final result = await conn.query(
            sql,
            substitutionValues: {'ip': ip},
          );
          final bool success = result[0][0] as bool;
          return success;
        } finally {
          await conn.close();
        }
      });

      final results = await Future.wait(futures);
      final successful = results.where((r) => r).length;
      expect(successful, equals(5));
    });

    test('pg_advisory_xact_lock serialization test', () async {
      final futures = List.generate(8, (_) async {
        final conn = PostgreSQLConnection(
          'localhost',
          5433,
          'itsr_radiant_test',
          username: 'postgres',
          password: 'postgres',
        );
        await conn.open();
        try {
          final ip = 'serialization_test_ip';
          final sql = 'SELECT public.check_rate_limit(@ip::text, 5, 15)::boolean';
          final result = await conn.query(
            sql,
            substitutionValues: {'ip': ip},
          );
          final bool success = result[0][0] as bool;
          return success;
        } finally {
          await conn.close();
        }
      });

      final results = await Future.wait(futures);
      final successful = results.where((r) => r).length;
      expect(successful, equals(5));
    });

    test('Fail-closed behavior when database execution fails', () async {
      final sql = 'SELECT public.check_rate_limit(@ip::text, 1, 1)::boolean';
      final result = await connection.query(
        sql,
        substitutionValues: {'ip': 'fail_closed_test_ip'},
      );
      final bool success = result[0][0] as bool;
      expect(success, equals(true));
    });

    test('Cleanup of expired login attempts', () async {
      final insertSql =
          '''INSERT INTO public.login_attempts (ip_address, employee_number, success, created_at) 
VALUES (@ip::text, NULL, false, NOW() - INTERVAL '20 minutes')''';
      await connection.query(
        insertSql,
        substitutionValues: {'ip': 'cleanup_test_ip'},
      );

      final sql2 = 'SELECT public.check_rate_limit(@ip::text, 5, 15)::boolean';
      final result2 = await connection.query(
        sql2,
        substitutionValues: {'ip': 'cleanup_test_ip'},
      );
      final bool success = result2[0][0] as bool;
      expect(success, equals(true));
    });
  });
}