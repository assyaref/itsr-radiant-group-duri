// RLS Security Tests - REQUIRES LIVE SUPABASE STAGING ENVIRONMENT
// These tests must be run against a properly provisioned staging database
// Execute with: flutter test --dart-define-from-file=.env.staging test/staging/rls_security_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:itsr_radiant/constants/app_constants.dart';

// This file contains all the RLS validation tests that must pass in staging
// before production deployment. These tests verify that security policies
// are correctly enforced at the database level.

void main() {
  late SupabaseClient supabase;

  // Test credentials - must be created in staging environment first
  const testEmployees = {
    'employee1': {'email': 'employee1@test.com', 'password': 'testpass123'},
    'employee2': {'email': 'employee2@test.com', 'password': 'testpass123'},
    'itsupport': {'email': 'itsupport@test.com', 'password': 'testpass123'},
    'admin': {'email': 'admin@test.com', 'password': 'testpass123'},
  };

  setUpAll(() async {
    // Initialize Supabase with staging credentials
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      publishableKey: AppConstants.supabaseAnonKey,
    );
    supabase = Supabase.instance.client;
  });

  group('RLS Security Tests - Staging Only', () {
    test('Employee A cannot access Employee B\'s tickets', () async {
      // Login as employee1
      await supabase.auth.signInWithPassword(
        email: testEmployees['employee1']!['email']!,
        password: testEmployees['employee1']!['password']!,
      );

      // Attempt to access a ticket created by employee2
      final response = await supabase
          .from('tickets')
          .select()
          .eq('reporter_id', 'employee2-profile-id')
          .maybeSingle();

      // Should return null - access denied
      expect(response, isNull);
    });

    test(
      'Employees cannot view internal comments on their own tickets',
      () async {
        await supabase.auth.signInWithPassword(
          email: testEmployees['employee1']!['email']!,
          password: testEmployees['employee1']!['password']!,
        );

        // Get all comments on employee1's ticket
        final comments = await supabase
            .from('ticket_comments')
            .select()
            .eq('ticket_id', 'test-ticket-id');

        // No internal comments should be returned
        final hasInternalComments = (comments as List).any(
          (c) => c['is_internal'] == true,
        );
        expect(hasInternalComments, isFalse);
      },
    );

    test('IT Support can view all comments including internal ones', () async {
      await supabase.auth.signInWithPassword(
        email: testEmployees['itsupport']!['email']!,
        password: testEmployees['itsupport']!['password']!,
      );

      // IT should see all comments
      final comments = await supabase
          .from('ticket_comments')
          .select()
          .eq('ticket_id', 'test-ticket-id');

      // Should be able to see internal comments
      expect(comments, isNotEmpty);
    });

    test('Employees cannot create internal comments', () async {
      await supabase.auth.signInWithPassword(
        email: testEmployees['employee1']!['email']!,
        password: testEmployees['employee1']!['password']!,
      );

      // Attempt to create internal comment (should fail with RLS violation)
      expect(
        () => supabase.from('ticket_comments').insert({
          'ticket_id': 'test-ticket-id',
          'author_id': 'employee1-profile-id',
          'content': 'Hacked internal note',
          'is_internal': true,
        }),
        throwsA(isA<AuthException>()),
      );
    });

    test('Employees cannot modify protected ticket columns', () async {
      await supabase.auth.signInWithPassword(
        email: testEmployees['employee1']!['email']!,
        password: testEmployees['employee1']!['password']!,
      );

      // Attempt to change priority (protected column)
      expect(
        () => supabase
            .from('tickets')
            .update({'priority': 'critical'})
            .eq('id', 'employee1-ticket-id'),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('Unauthenticated users cannot access any data', () async {
      await supabase.auth.signOut();

      // Attempt to access tickets without login
      final tickets = await supabase.from('tickets').select();
      expect(tickets, isEmpty);
    });

    test('Only IT/Admin can create activity logs', () async {
      await supabase.auth.signInWithPassword(
        email: testEmployees['employee1']!['email']!,
        password: testEmployees['employee1']!['password']!,
      );

      // Regular employees should not be able to create activity logs
      expect(
        () => supabase.from('ticket_activity_log').insert({
          'ticket_id': 'test-ticket-id',
          'actor_id': 'employee1-profile-id',
          'action': 'fake_activity',
          'created_at': DateTime.now().toIso8601String(),
        }),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('IT Support can update ticket statuses', () async {
      await supabase.auth.signInWithPassword(
        email: testEmployees['itsupport']!['email']!,
        password: testEmployees['itsupport']!['password']!,
      );

      // IT should be able to update ticket status
      final updateResult = await supabase
          .from('tickets')
          .update({'status': 'in_progress'})
          .eq('id', 'test-ticket-id');

      expect(updateResult.error, isNull);
    });
  });
}
