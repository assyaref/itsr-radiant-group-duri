import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:itsr_radiant/constants/app_constants.dart';
import 'package:itsr_radiant/utils/error_messages.dart';
import 'package:itsr_radiant/utils/validators.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  String b(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b({'alg': 'HS256'})}.${b(payload)}.signature';
}

void main() {
  group('Validators', () {
    test('employee number is normalised and validated', () {
      expect(Validators.normalizeEmployeeNumber(' emp001 '), 'EMP001');
      expect(Validators.employeeNumber('emp001'), isNull);
      expect(Validators.employeeNumber(''), isNotNull);
      expect(Validators.employeeNumber('EMP-001'), isNotNull);
      expect(Validators.employeeNumber('E'), isNotNull);
    });

    test('ticket fields mirror database CHECK constraints', () {
      expect(Validators.subject('ab'), isNotNull);
      expect(Validators.subject('abc'), isNull);
      expect(Validators.subject('x' * 201), isNotNull);
      expect(Validators.description('1234'), isNotNull);
      expect(Validators.description('12345'), isNull);
    });

    test('passwords and emails', () {
      expect(Validators.loginPassword('1234'), isNull);
      expect(Validators.loginPassword('12345'), isNull);
      expect(Validators.loginPassword('123456'), isNull);
      expect(Validators.loginPassword('abcde'), isNotNull);
      expect(Validators.newPassword('1234'), isNull);
      expect(Validators.newPassword('abcde'), isNotNull);
      expect(Validators.newPassword('123'), isNotNull);
      expect(Validators.newPassword('abc12'), isNotNull);
      expect(Validators.newPassword('abc123'), isNull);
      expect(Validators.newPassword('1234567'), isNull);
      expect(Validators.newPassword('12345678'), isNull);
      expect(Validators.email('a@b.co'), isNull);
      expect(Validators.email('nope'), isNotNull);
      expect(Validators.email('', required: false), isNull);
    });

    test('search input cannot alter PostgREST or-filter structure', () {
      final s = Validators.sanitizeSearch('printer),status.eq.closed,(x*');
      expect(s.contains(','), isFalse);
      expect(s.contains('('), isFalse);
      expect(s.contains(')'), isFalse);
      expect(s.contains('*'), isFalse);
      expect(s.contains('.'), isFalse);
    });
  });

  group('Client key hygiene', () {
    test('no credentials are compiled in by default', () {
      expect(AppConstants.supabaseUrl, isEmpty);
      expect(AppConstants.supabaseAnonKey, isEmpty);
      expect(AppConstants.hasValidConfiguration, isFalse);
    });

    test('server-side secret keys are rejected, public keys accepted', () {
      expect(AppConstants.looksLikeSecretKey('sb_secret_abc'), isTrue);
      expect(
        AppConstants.looksLikeSecretKey(_fakeJwt({'role': 'service_role'})),
        isTrue,
      );
      expect(
        AppConstants.looksLikeSecretKey(_fakeJwt({'role': 'anon'})),
        isFalse,
      );
      expect(AppConstants.looksLikeSecretKey('sb_publishable_abc'), isFalse);
    });

    test('no service-role key or secret appears anywhere in lib/ or web/', () {
      final offenders = <String>[];
      for (final dir in ['lib', 'web']) {
        for (final f in Directory(
          dir,
        ).listSync(recursive: true).whereType<File>()) {
          if (!(f.path.endsWith('.dart') ||
              f.path.endsWith('.html') ||
              f.path.endsWith('.json'))) {
            continue;
          }
          final text = f.readAsStringSync();
          if (RegExp(r'sb_secret_[A-Za-z0-9]').hasMatch(text) ||
              RegExp(r'SUPABASE_SERVICE_ROLE_KEY').hasMatch(text) ||
              RegExp(r'eyJ[A-Za-z0-9_-]{20,}\.').hasMatch(text)) {
            offenders.add(f.path);
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('no hard-coded notification email addresses in the app', () {
      final hits = <String>[];
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final m = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+')
            .allMatches(f.readAsStringSync());
        hits.addAll(m.map((e) => '${f.path}: ${e.group(0)}'));
      }
      expect(hits, isEmpty);
    });
  });

  test('UI status transitions are a subset of the database transitions', () {
    final sql = File('supabase/migrations/20261108000300_ticket_workflow.sql')
        .readAsStringSync();
    final dbPairs = RegExp(r"\('(\w+)',\s*'(\w+)'\)")
        .allMatches(sql)
        .map((m) => '${m.group(1)}->${m.group(2)}')
        .toSet();
    expect(dbPairs, isNotEmpty);
    for (final e in AppConstants.staffTransitions.entries) {
      for (final to in e.value) {
        expect(
          dbPairs,
          contains('${e.key}->$to'),
          reason: 'UI offers ${e.key}->$to',
        );
      }
    }
  });

  group('friendlyError', () {
    test('permission errors are explained without internals', () {
      final msg = friendlyError(
        const PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501',
        ),
      );
      expect(msg, 'You do not have permission to perform this action.');
    });
    test('database business-rule messages pass through', () {
      expect(
        friendlyError(
          const PostgrestException(
            message: 'A resolution description is required to resolve a ticket',
            code: '23514',
          ),
        ),
        contains('resolution'),
      );
    });
    test('function errors surface the server message', () {
      expect(
        friendlyError(
          const FunctionException(
            status: 403,
            details: {'error': 'Administrator access required'},
          ),
        ),
        'Administrator access required',
      );
    });
    test('unknown errors become generic', () {
      expect(
        friendlyError(Exception('stack trace with secrets')),
        'Something went wrong. Please try again.',
      );
      expect(friendlyError(const RateLimited()), contains('15 minutes'));
    });
  });
}
