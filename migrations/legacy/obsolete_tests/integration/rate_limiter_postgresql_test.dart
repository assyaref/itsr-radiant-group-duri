import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';

void main() {
  late PostgreSQLConnection connection;

  setUpAll(() async {
    connection = PostgreSQLConnection('localhost', 5433, 'itsr_radiant_test',
        username: 'postgres', password: 'postgres');
    await connection.open();
  });

  setUp(() async {
    // Clear all test data before each test to ensure isolation
    await connection.execute('TRUNCATE public.profiles, public.tickets, public.ticket_activity_log, public.ticket_comments, public.login_attempts CASCADE;');
  });

  tearDownAll(() async {
    await connection.close();
  });

  group('PostgreSQL Integration Tests', () {
    test('Database connection can execute query', () async {
      final result = await connection.query('SELECT 1 AS test');
      expect(result.length, equals(1));
    });

    test('Database connection can execute ALTER TABLE to enable RLS', () async {
      await connection.execute(
          'ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;');
    });

    test('Database connection can execute multiple ALTER statements for RLS', () async {
      await connection.execute(
          'ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;');
      await connection.execute(
          'ALTER TABLE public.ticket_activity_log ENABLE ROW LEVEL SECURITY;');
      await connection.execute(
          'ALTER TABLE public.ticket_comments ENABLE ROW LEVEL SECURITY;');
    });
  });
}