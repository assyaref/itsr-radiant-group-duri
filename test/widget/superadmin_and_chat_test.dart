import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itsr_radiant/constants/app_constants.dart';
import 'package:itsr_radiant/models/attachment_model.dart';
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

    testWidgets('floating chat opens, closes, and keeps the draft', (t) async {
      await pumpApp(
        t,
        const TicketDetailScreen(ticketId: '1'),
        auth: FakeAuthRepository(profile: user('emp1', 'employee')),
        tickets: FakeTicketRepository(tickets: [ticket('1')]),
      );
      expect(find.byKey(const Key('comment_field')), findsNothing);
      await t.tap(find.text('Komentar'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('comment_field')), 'draft');
      await t.tap(find.byTooltip('Tutup komentar'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('comment_field')), findsNothing);
      await t.tap(find.text('Komentar'));
      await t.pumpAndSettle();
      expect(find.text('draft'), findsOneWidget);
      // Switching tabs tucks the chat away again.
      await t.tap(find.text('Lampiran'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('comment_field')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('attachments appear in the chat (image thumbnail, file chip)', (
      t,
    ) async {
      // 1x1 transparent PNG.
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      );
      final files = FakeAttachmentRepository(
        files: [
          AttachmentModel(
            id: 'att1',
            ticketId: '1',
            fileName: 'tempel_1.png',
            mimeType: 'image/png',
            fileSize: png.length,
            uploadedBy: 'emp1',
            createdAt: DateTime.utc(2026, 11, 2, 8),
            uploaderName: 'Emp Name',
          ),
          AttachmentModel(
            id: 'att2',
            ticketId: '1',
            fileName: 'laporan.pdf',
            mimeType: 'application/pdf',
            fileSize: 2048,
            uploadedBy: 'it1',
            createdAt: DateTime.utc(2026, 11, 2, 9),
            uploaderName: 'Tech Name',
          ),
        ],
        bytes: {'att1': png},
      );
      await pumpApp(
        t,
        const TicketDetailScreen(ticketId: '1'),
        auth: FakeAuthRepository(profile: user('emp1', 'employee')),
        tickets: FakeTicketRepository(tickets: [ticket('1')]),
        attachments: files,
        size: phone,
      );
      await t.tap(find.text('Komentar'));
      await t.pumpAndSettle();
      final image = find.byKey(const Key('chat_image_att1'));
      expect(image, findsOneWidget);
      // Reporter's image on the right, IT's PDF on the left.
      expect(t.getRect(image).center.dx, greaterThan(phone.width / 2));
      final pdf = find.text('laporan.pdf');
      expect(pdf, findsOneWidget);
      expect(t.getRect(pdf).left, lessThan(phone.width / 2));
      // Tapping the thumbnail opens the full-size viewer.
      await t.ensureVisible(image);
      await t.pumpAndSettle();
      await t.tap(image);
      await t.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('chat edit and delete', () {
    List<CommentModel> chat() => [
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

    Future<FakeTicketRepository> open(
      WidgetTester t,
      String role,
      String id,
    ) async {
      final repo = FakeTicketRepository(tickets: [ticket('1')])
        ..comments = chat();
      await pumpApp(
        t,
        const TicketDetailScreen(ticketId: '1'),
        auth: FakeAuthRepository(profile: user(id, role)),
        tickets: repo,
        size: const Size(1280, 900),
      );
      await t.tap(find.text('Komentar'));
      await t.pumpAndSettle();
      return repo;
    }

    testWidgets('author edits own comment; no menu on others', (t) async {
      final repo = await open(t, 'employee', 'emp1');
      expect(find.byKey(const Key('chat_menu_c1')), findsOneWidget);
      expect(find.byKey(const Key('chat_menu_c2')), findsNothing);

      await t.tap(find.byKey(const Key('chat_menu_c1')));
      await t.pumpAndSettle();
      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField), 'Printer error lagi');
      await t.tap(find.text('Simpan'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('edit:c1:Printer error lagi'));
      expect(find.text('Printer error lagi'), findsOneWidget);
      expect(find.text('diedit'), findsOneWidget);
    });

    testWidgets('author deletes own comment -> placeholder', (t) async {
      final repo = await open(t, 'employee', 'emp1');
      await t.tap(find.byKey(const Key('chat_menu_c1')));
      await t.pumpAndSettle();
      await t.tap(find.text('Hapus'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Hapus'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('delete:c1'));
      expect(find.text('Printer masih error'), findsNothing);
      expect(find.text('Pesan ini telah dihapus'), findsOneWidget);
      // A deleted comment has no menu any more.
      expect(find.byKey(const Key('chat_menu_c1')), findsNothing);
    });

    testWidgets('administrator may delete but not edit others', (t) async {
      await open(t, 'administrator', 'adm1');
      await t.tap(find.byKey(const Key('chat_menu_c2')));
      await t.pumpAndSettle();
      expect(find.text('Hapus'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('IT support cannot touch the reporter\'s comment', (t) async {
      await open(t, 'it_support', 'it1');
      expect(find.byKey(const Key('chat_menu_c1')), findsNothing);
      expect(find.byKey(const Key('chat_menu_c2')), findsOneWidget);
    });

    testWidgets('uploader deletes an image from the chat', (t) async {
      final files = FakeAttachmentRepository(
        files: [
          AttachmentModel(
            id: 'att1',
            ticketId: '1',
            fileName: 'laporan.pdf',
            mimeType: 'application/pdf',
            fileSize: 2048,
            uploadedBy: 'emp1',
            createdAt: DateTime.utc(2026, 11, 2, 10),
            uploaderName: 'Emp Name',
          ),
        ],
      );
      await pumpApp(
        t,
        const TicketDetailScreen(ticketId: '1'),
        auth: FakeAuthRepository(profile: user('emp1', 'employee')),
        tickets: FakeTicketRepository(tickets: [ticket('1')]),
        attachments: files,
      );
      await t.tap(find.text('Komentar'));
      await t.pumpAndSettle();
      expect(find.text('laporan.pdf'), findsOneWidget);
      await t.tap(find.byKey(const Key('chat_menu_att1')));
      await t.pumpAndSettle();
      await t.tap(find.text('Hapus'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Hapus'));
      await t.pumpAndSettle();
      expect(files.files, isEmpty);
      expect(find.text('laporan.pdf'), findsNothing);
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
