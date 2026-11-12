import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itsr_radiant/models/app_notification.dart';
import 'package:itsr_radiant/screens/employee/employee_tickets_screen.dart';
import 'package:itsr_radiant/screens/employee/notifications_screen.dart';
import 'package:itsr_radiant/screens/employee/profile_screen.dart';
import 'package:itsr_radiant/screens/employee/ticket_submitted_screen.dart';

import '../support/fakes.dart';

const phone = Size(390, 844);

void main() {
  final emp = user('emp1', 'employee', name: 'Andi Pratama');

  testWidgets('ticket list: status chips filter by group (Selesai = resolved + closed)', (t) async {
    final repo = FakeTicketRepository(tickets: [
      ticket('1', subject: 'Open one'),
      ticket('2', subject: 'Working', status: 'in_progress'),
      ticket('3', subject: 'Fixed', status: 'resolved'),
      ticket('4', subject: 'Closed one', status: 'closed'),
    ]);
    await pumpApp(t, const EmployeeTicketsScreen(), auth: FakeAuthRepository(profile: emp), tickets: repo, size: phone);
    expect(find.text('Semua Tiket'), findsOneWidget);
    expect(find.text('Open one'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('status_group_Selesai')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('status_group_Selesai')));
    await t.pumpAndSettle();
    expect(find.text('Fixed'), findsOneWidget);
    expect(find.text('Closed one'), findsOneWidget);
    expect(find.text('Open one'), findsNothing);
    expect(find.text('Working'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('notifications: list and Tiket / Sistem tabs', (t) async {
    final repo = FakeTicketRepository()
      ..notifications = [
        AppNotification(id: 'a', kind: 'resolved', title: 'Tiket selesai',
            body: 'Tiket ITSR-00003 telah selesai.', time: DateTime.now().subtract(const Duration(hours: 2)),
            ticketId: '3'),
        AppNotification(id: 'b', kind: 'comment', title: 'Komentar baru',
            body: 'Budi memberikan komentar pada tiket ITSR-00001.',
            time: DateTime.now().subtract(const Duration(minutes: 30)), ticketId: '1'),
        AppNotification(id: 'c', kind: 'system', title: 'Tiket diperbarui',
            body: 'Status diubah otomatis.', time: DateTime.now().subtract(const Duration(days: 1))),
      ];
    await pumpApp(t, const NotificationsScreen(), auth: FakeAuthRepository(profile: emp), tickets: repo, size: phone);
    expect(find.text('Tiket selesai'), findsOneWidget);
    expect(find.text('Komentar baru'), findsOneWidget);
    expect(find.text('2 jam lalu'), findsOneWidget);
    await t.tap(find.text('Sistem'));
    await t.pumpAndSettle();
    expect(find.text('Tiket diperbarui'), findsOneWidget);
    expect(find.text('Komentar baru'), findsNothing);
  });

  testWidgets('profile: account info and change password', (t) async {
    final auth = FakeAuthRepository(profile: emp);
    await pumpApp(t, const ProfileScreen(), auth: auth, size: phone);
    expect(find.text('Andi Pratama'), findsOneWidget);
    for (final s in ['Informasi Akun', 'Ubah Password', 'Notifikasi', 'Bantuan', 'Tentang Aplikasi', 'Keluar']) {
      expect(find.text(s), findsOneWidget, reason: 'menu "$s"');
    }
    await t.tap(find.byKey(const Key('profile_password')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('new_password_field')), 'short');
    await t.tap(find.byKey(const Key('save_password_button')));
    await t.pump();
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    await t.enterText(find.byKey(const Key('new_password_field')), 'NewSecret123');
    await t.enterText(find.byKey(const Key('confirm_password_field')), 'Different123');
    await t.tap(find.byKey(const Key('save_password_button')));
    await t.pump();
    expect(find.text('Password tidak sama'), findsOneWidget);
    await t.enterText(find.byKey(const Key('confirm_password_field')), 'NewSecret123');
    await t.tap(find.byKey(const Key('save_password_button')));
    await t.pumpAndSettle();
    expect(auth.calls, contains('changePassword'));
    expect(find.text('Password berhasil diubah'), findsOneWidget);
  });

  testWidgets('submitted screen shows the ticket number', (t) async {
    final repo = FakeTicketRepository(tickets: [ticket('7')]);
    await pumpApp(t, const TicketSubmittedScreen(ticketId: '7'),
        auth: FakeAuthRepository(profile: emp), tickets: repo, size: phone);
    expect(find.text('Tiket Berhasil Dikirim!'), findsOneWidget);
    expect(find.text('ITSR-00007'), findsOneWidget);
    expect(find.text('Kembali ke Beranda'), findsOneWidget);
  });

  for (final (name, screen) in [
    ('notifications', const NotificationsScreen()),
    ('profile', const ProfileScreen()),
    ('ticket list', const EmployeeTicketsScreen()),
    ('submitted', const TicketSubmittedScreen(ticketId: '1')),
  ]) {
    testWidgets('no overflow on a 320px-wide phone: $name', (t) async {
      final repo = FakeTicketRepository(tickets: [ticket('1')]);
      await pumpApp(t, screen, auth: FakeAuthRepository(profile: emp), tickets: repo, size: const Size(320, 640));
      expect(t.takeException(), isNull);
    });
  }
}
