import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itsr_radiant/constants/app_constants.dart';
import 'package:itsr_radiant/models/comment_model.dart';
import 'package:itsr_radiant/screens/admin/data_management_screen.dart';
import 'package:itsr_radiant/screens/admin/users_screen.dart';
import 'package:itsr_radiant/utils/browser_files.dart';
import 'package:itsr_radiant/utils/user_import.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:itsr_radiant/screens/ticket_detail_screen.dart';

import '../support/fakes.dart';

const desktop = Size(1440, 900);
const phone = Size(390, 844);

void main() {
  group('roles', () {
    test('superadmin is staff + admin; only superadmin may delete', () {
      final s = user('s', 'superadmin');
      expect(s.isStaff, isTrue);
      expect(s.isAdmin, isTrue);
      expect(s.isSuperAdmin, isTrue);
      expect(user('a', 'administrator').isSuperAdmin, isFalse);
      expect(AppConstants.roles, isNot(contains('superadmin')));
    });
  });

  group('delete ticket', () {
    testWidgets('administrator does not see the delete button', (t) async {
      await pumpApp(
        t,
        const TicketDetailScreen(ticketId: '1'),
        auth: FakeAuthRepository(profile: user('ad1', 'administrator')),
        tickets: FakeTicketRepository(tickets: [ticket('1')]),
        size: desktop,
      );
      expect(find.byKey(const Key('delete_ticket_button')), findsNothing);
    });

    testWidgets('superadmin deletes after confirming', (t) async {
      final repo = FakeTicketRepository(tickets: [ticket('1')]);
      await pumpApp(
        t,
        const TicketDetailScreen(ticketId: '1'),
        auth: FakeAuthRepository(profile: user('su1', 'superadmin')),
        tickets: repo,
        size: desktop,
      );
      final btn = find.byKey(const Key('delete_ticket_button'));
      await t.ensureVisible(btn);
      await t.tap(btn);
      await t.pumpAndSettle();
      expect(repo.calls, isNot(contains('delete:1')));
      await t.tap(find.widgetWithText(FilledButton, 'Hapus permanen'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('delete:1'));
    });
  });

  group('backup & purge', () {
    testWidgets('backup calls the export', (t) async {
      final admin = FakeAdminRepository();
      await pumpApp(
        t,
        const DataManagementScreen(),
        auth: FakeAuthRepository(profile: user('ad1', 'administrator')),
        admin: admin,
      );
      await t.tap(find.byKey(const Key('backup_button')));
      await t.pumpAndSettle();
      expect(admin.calls, contains('backup'));
    });

    testWidgets('purge requires the exact phrase', (t) async {
      final admin = FakeAdminRepository();
      await pumpApp(
        t,
        const DataManagementScreen(),
        auth: FakeAuthRepository(profile: user('ad1', 'administrator')),
        admin: admin,
      );
      await t.tap(find.byKey(const Key('purge_button')));
      await t.pumpAndSettle();
      final confirm = find.byKey(const Key('purge_confirm_button'));
      await t.enterText(find.byKey(const Key('purge_confirm_field')), 'hapus');
      await t.pump();
      expect(t.widget<FilledButton>(confirm).onPressed, isNull);
      await t.enterText(
        find.byKey(const Key('purge_confirm_field')),
        kPurgeConfirmPhrase,
      );
      await t.pump();
      await t.tap(confirm);
      await t.pumpAndSettle();
      // Backup-first is ticked by default.
      expect(admin.calls, ['backup', 'purge:$kPurgeConfirmPhrase']);
    });
  });

  group('chat bubbles', () {
    testWidgets('reporter on the right, IT support on the left', (t) async {
      final repo = FakeTicketRepository(tickets: [ticket('1')]);
      repo.comments = [
        CommentModel(
          id: 'c1',
          ticketId: '1',
          authorId: 'emp1',
          content: 'Printer masih error',
          isInternal: false,
          createdAt: DateTime.utc(2026, 11, 2, 8),
          authorName: 'Emp Name',
        ),
        CommentModel(
          id: 'c2',
          ticketId: '1',
          authorId: 'it1',
          content: 'Sedang kami cek',
          isInternal: false,
          createdAt: DateTime.utc(2026, 11, 2, 9),
          authorName: 'Tech Name',
        ),
      ];
      await pumpApp(
        t,
        const TicketDetailScreen(ticketId: '1'),
        auth: FakeAuthRepository(profile: user('emp1', 'employee')),
        tickets: repo,
        size: phone,
      );
      await t.tap(find.text('Komentar'));
      await t.pumpAndSettle();
      final userMsg = t.getRect(find.text('Printer masih error'));
      final itMsg = t.getRect(find.text('Sedang kami cek'));
      expect(userMsg.center.dx, greaterThan(phone.width / 2));
      expect(itMsg.center.dx, lessThan(phone.width / 2));
      // Chronological: the newer IT reply is below the user's message.
      expect(itMsg.top, greaterThan(userMsg.top));
      expect(find.text('IT SUPPORT'), findsOneWidget);
      expect(find.text('Anda'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('superadmin is hidden and locked', () {
    final people = [
      user('ad1', 'administrator', name: 'Admin One'),
      user('su1', 'superadmin', name: 'Super Admin'),
    ];

    testWidgets('administrator never sees the superadmin', (t) async {
      final admin = FakeAdminRepository()..users = people;
      await pumpApp(
        t,
        const UsersScreen(),
        auth: FakeAuthRepository(profile: people[0]),
        admin: admin,
      );
      expect(find.textContaining('Super Admin'), findsNothing);
      expect(find.textContaining('Admin One'), findsOneWidget);
    });

    testWidgets('superadmin row has no edit actions', (t) async {
      final admin = FakeAdminRepository()..users = people;
      await pumpApp(
        t,
        const UsersScreen(),
        auth: FakeAuthRepository(profile: people[1]),
        admin: admin,
      );
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });
  });

  group('import & restore', () {
    tearDown(() => debugPickedFiles = null);

    testWidgets('import users from CSV', (t) async {
      final admin = FakeAdminRepository()
        ..users = [user('ad1', 'administrator')];
      await pumpApp(
        t,
        const UsersScreen(),
        auth: FakeAuthRepository(profile: user('ad1', 'administrator')),
        admin: admin,
      );
      await t.tap(find.byKey(const Key('user_template_button')));
      await t.pumpAndSettle();
      expect(debugDownloads, contains('template-import-user-itsr.xlsx'));

      debugPickedFiles = [
        PickedFile(
          name: 'u.csv',
          mimeType: 'text/csv',
          bytes: Uint8List.fromList(
            utf8.encode(
              [
                'NIK;Nama Lengkap;Email;Departemen;Role;No HP;Password',
                'E100;Satu;satu@x.com;HR;employee;;rahasia123',
                'E101;Dua;bad;HR;employee;;rahasia123',
              ].join('\n'),
            ),
          ),
        ),
      ];
      await t.tap(find.byKey(const Key('user_import_button')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pick_import_file')));
      await t.pumpAndSettle();
      expect(find.text('Import 1 pengguna'), findsOneWidget);
      await t.tap(find.byKey(const Key('run_user_import')));
      await t.pumpAndSettle();
      expect(admin.calls, ['createUser:E100:employee']);
      expect(find.text('Tutup'), findsOneWidget);
      expect(UserImport.maxRows, 500);
    });

    testWidgets('restore requires phrase and sends mode', (t) async {
      final admin = FakeAdminRepository();
      debugPickedFiles = [
        PickedFile(
          name: 'b.json',
          mimeType: 'application/json',
          bytes: Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'format': 'itsr-backup',
                'tables': {'tickets': []},
              }),
            ),
          ),
        ),
      ];
      await pumpApp(
        t,
        const DataManagementScreen(),
        auth: FakeAuthRepository(profile: user('ad1', 'administrator')),
        admin: admin,
      );
      await t.tap(find.byKey(const Key('restore_button')));
      await t.pumpAndSettle();
      final ok = find.byKey(const Key('restore_confirm_button'));
      expect(t.widget<FilledButton>(ok).onPressed, isNull);
      await t.tap(find.byKey(const Key('restore_mode_replace')));
      await t.enterText(
        find.byKey(const Key('restore_confirm_field')),
        kRestoreConfirmPhrase,
      );
      await t.pump();
      await t.tap(ok);
      await t.pumpAndSettle();
      expect(admin.calls, ['backup', 'restore:replace:$kRestoreConfirmPhrase']);
    });
  });
}
