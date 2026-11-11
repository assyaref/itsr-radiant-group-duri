import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itsr_radiant/models/comment_model.dart';
import 'package:itsr_radiant/screens/create_ticket_screen.dart';
import 'package:itsr_radiant/screens/dashboard_screen.dart';
import 'package:itsr_radiant/screens/login_screen.dart';
import 'package:itsr_radiant/screens/my_tickets_screen.dart';
import 'package:itsr_radiant/screens/ticket_detail_screen.dart';
import 'package:itsr_radiant/utils/error_messages.dart';
import 'package:itsr_radiant/widgets/app_shell.dart';

import '../support/fakes.dart';

const phone = Size(390, 844);
const desktop = Size(1440, 900);

Future<void> openCompanyLogin(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const Key('company_login_entry')));
  await t.tap(find.byKey(const Key('company_login_entry')));
  await t.pumpAndSettle();
}

void main() {
  group('Login', () {
    testWidgets('validates empty form without calling the server', (t) async {
      final auth = FakeAuthRepository();
      await pumpApp(t, const LoginScreen(), auth: auth, size: phone);
      await openCompanyLogin(t);
      await t.tap(find.byKey(const Key('login_button')));
      await t.pump();
      expect(find.text('Please enter your employee number'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('invalid credentials show a generic, safe message', (t) async {
      final auth = FakeAuthRepository(signInError: const InvalidCredentials());
      await pumpApp(t, const LoginScreen(), auth: auth, size: phone);
      await openCompanyLogin(t);
      await t.enterText(find.byKey(const Key('employee_number_field')), 'emp001');
      await t.enterText(find.byKey(const Key('password_field')), 'wrongpass');
      await t.tap(find.byKey(const Key('login_button')));
      await t.pumpAndSettle();
      expect(auth.calls, ['signIn:EMP001'], reason: 'employee number normalised to upper case');
      expect(find.byKey(const Key('login_error')), findsOneWidget);
      expect(find.textContaining('Authentication failed'), findsOneWidget);
    });

    testWidgets('rate limiting message is shown', (t) async {
      final auth = FakeAuthRepository(signInError: const RateLimited());
      await pumpApp(t, const LoginScreen(), auth: auth, size: desktop);
      await openCompanyLogin(t);
      await t.enterText(find.byKey(const Key('employee_number_field')), 'EMP001');
      await t.enterText(find.byKey(const Key('password_field')), 'whatever1');
      await t.tap(find.byKey(const Key('login_button')));
      await t.pumpAndSettle();
      expect(find.textContaining('15 minutes'), findsOneWidget);
    });

    testWidgets('welcome page matches the design: both sign-in options', (t) async {
      await pumpApp(t, const LoginScreen(), auth: FakeAuthRepository(), size: phone);
      expect(find.text('IT Support'), findsOneWidget);
      expect(find.text('Cabang Duri'), findsOneWidget);
      expect(find.textContaining('Solusi Cepat'), findsOneWidget);
      expect(find.byKey(const Key('email_login_entry')), findsOneWidget);
      expect(find.text('atau'), findsOneWidget);
      expect(find.byKey(const Key('company_login_entry')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('email sign-in sends the lower-cased email', (t) async {
      final auth = FakeAuthRepository(signInError: const InvalidCredentials());
      await pumpApp(t, const LoginScreen(), auth: auth, size: phone);
      await t.tap(find.byKey(const Key('email_login_entry')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('email_field')), 'Andi@Radiant.co.id');
      await t.enterText(find.byKey(const Key('password_field')), 'secret12');
      await t.ensureVisible(find.byKey(const Key('login_button')));
      await t.tap(find.byKey(const Key('login_button')));
      await t.pumpAndSettle();
      expect(auth.calls, ['signIn:andi@radiant.co.id']);
      expect(find.byKey(const Key('login_error')), findsOneWidget);
    });

    testWidgets('back returns to the welcome page', (t) async {
      await pumpApp(t, const LoginScreen(), auth: FakeAuthRepository(), size: phone);
      await openCompanyLogin(t);
      await t.tap(find.byKey(const Key('login_back_button')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('company_login_entry')), findsOneWidget);
    });
  });

  group('Create ticket', () {
    testWidgets('requires subject, category and description', (t) async {
      final repo = FakeTicketRepository();
      await pumpApp(t, const CreateTicketScreen(),
          auth: FakeAuthRepository(profile: user('emp1', 'employee')), tickets: repo, size: phone);
      await t.ensureVisible(find.byKey(const Key('submit_ticket_button')));
      await t.tap(find.byKey(const Key('submit_ticket_button')));
      await t.pump();
      expect(find.text('Please enter a subject'), findsOneWidget);
      expect(find.text('Please select a category'), findsOneWidget);
      expect(find.text('Please describe the problem'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    testWidgets('loads categories from the database and submits', (t) async {
      final repo = FakeTicketRepository();
      await pumpApp(t, const CreateTicketScreen(),
          auth: FakeAuthRepository(profile: user('emp1', 'employee')), tickets: repo, size: desktop);
      await t.enterText(find.byKey(const Key('subject_field')), 'VPN is down');
      await t.enterText(find.byKey(const Key('description_field')), 'Cannot connect since 8am');
      await t.tap(find.byKey(const Key('category_field')));
      await t.pumpAndSettle();
      await t.tap(find.text('Network').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('submit_ticket_button')));
      await t.pump();
      expect(repo.calls.first, 'create:emp1:VPN is down:Network:medium');
    });
  });

  group('Ticket detail', () {
    testWidgets('ticket content is exposed to screen readers (semantics), not as empty fields', (t) async {
      final handle = t.ensureSemantics();
      final repo = FakeTicketRepository(
          tickets: [ticket('1', status: 'resolved', assignedToId: 'it1', resolution: 'Replaced toner')]);
      repo.comments = [
        CommentModel(id: 'c', ticketId: '1', authorId: 'emp1', content: 'It jams on page two',
            isInternal: false, createdAt: DateTime.utc(2026, 11, 2), authorName: 'Emp Name'),
      ];
      await pumpApp(t, const TicketDetailScreen(ticketId: '1'),
          auth: FakeAuthRepository(profile: user('emp1', 'employee')), tickets: repo, size: desktop);
      for (final s in ['ITSR-00001', 'Printer broken', 'It does not print anything',
                       'Replaced toner', 'It jams on page two']) {
        // Flutter merges adjacent text into one semantics node: match as substring.
        expect(find.bySemanticsLabel(RegExp(RegExp.escape(s))), findsWidgets,
            reason: '"$s" must be readable by assistive tech');
      }
      handle.dispose();
    });

    testWidgets('employee: no IT actions, no internal-note option, can reopen resolved', (t) async {
      final repo = FakeTicketRepository(
          tickets: [ticket('1', status: 'resolved', assignedToId: 'it1', resolution: 'Replaced toner')]);
      await pumpApp(t, const TicketDetailScreen(ticketId: '1'),
          auth: FakeAuthRepository(profile: user('emp1', 'employee')), tickets: repo, size: phone);
      expect(find.text('IT Support actions'), findsNothing);
      expect(find.text('Internal work note'), findsNothing);
      expect(find.text('Replaced toner'), findsOneWidget);
      expect(find.text('Yes, close ticket'), findsOneWidget);
      await t.drag(find.byType(ListView).first, const Offset(0, -1500));
      await t.pumpAndSettle();
      await t.tap(find.text('Reopen'));
      await t.pumpAndSettle();
      await t.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), 'Still not printing');
      await t.tap(find.widgetWithText(FilledButton, 'Reopen'));
      await t.pumpAndSettle();
      expect(repo.calls, contains('reporter:1:reopen:Still not printing'));
    });

    testWidgets('IT support: accept, then resolve requires a resolution', (t) async {
      final repo = FakeTicketRepository(tickets: [ticket('1')]);
      repo.comments = [
        CommentModel(id: 'c', ticketId: '1', authorId: 'it1', content: 'Checked cables',
            isInternal: true, createdAt: DateTime.utc(2026, 11, 2), authorName: 'Tech Name'),
      ];
      await pumpApp(t, const TicketDetailScreen(ticketId: '1'),
          auth: FakeAuthRepository(profile: user('it1', 'it_support')), tickets: repo, size: desktop);
      expect(find.text('INTERNAL NOTE'), findsOneWidget);
      expect(find.text('Internal work note'), findsOneWidget);
      // the server moves the ticket on; the screen reloads after the action
      repo.tickets = [ticket('1', status: 'in_progress', assignedToId: 'it1')];
      await t.tap(find.byKey(const Key('accept_ticket_button')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('update:1:status=null:assignee=it1:unassign=false:resolution=null'));
      expect(find.byKey(const Key('accept_ticket_button')), findsNothing);
      await t.tap(find.byKey(const Key('status_resolved')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Resolve'));
      await t.pumpAndSettle();
      expect(find.text('Please enter at least 5 characters'), findsOneWidget);
      await t.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextFormField)), 'Re-seated network cable');
      await t.tap(find.widgetWithText(FilledButton, 'Resolve'));
      await t.pumpAndSettle();
      expect(repo.calls,
          contains('update:1:status=resolved:assignee=null:unassign=false:resolution=Re-seated network cable'));
    });

    testWidgets('server errors are shown, not crashed on', (t) async {
      final repo = FakeTicketRepository(tickets: [ticket('1')])
        ..failWith = Exception('boom');
      await pumpApp(t, const TicketDetailScreen(ticketId: '1'),
          auth: FakeAuthRepository(profile: user('emp1', 'employee')), tickets: repo, size: phone);
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Lists, dashboard and responsive shell', () {
    testWidgets('My Tickets shows empty state with call to action', (t) async {
      await pumpApp(t, const MyTicketsScreen(),
          auth: FakeAuthRepository(profile: user('emp1', 'employee')), size: phone);
      expect(find.text('You have not submitted any tickets'), findsOneWidget);
      expect(find.text('Create a ticket'), findsOneWidget);
    });

    testWidgets('My Tickets lists only own tickets', (t) async {
      final repo = FakeTicketRepository(tickets: [
        ticket('1', subject: 'Mine'),
        ticket('2', subject: 'Not mine', reporterId: 'other'),
      ]);
      await pumpApp(t, const MyTicketsScreen(),
          auth: FakeAuthRepository(profile: user('emp1', 'employee')), tickets: repo, size: desktop);
      expect(find.text('Mine'), findsOneWidget);
      expect(find.text('Not mine'), findsNothing);
    });

    testWidgets('employee dashboard shows stats and no staff sections', (t) async {
      final repo = FakeTicketRepository(tickets: [ticket('1'), ticket('2', status: 'resolved')]);
      await pumpApp(t, const DashboardScreen(),
          auth: FakeAuthRepository(profile: user('emp1', 'employee', name: 'Ani')), tickets: repo, size: phone);
      expect(find.text('Welcome, Ani'), findsOneWidget);
      expect(find.text('Total tickets'), findsOneWidget);
      expect(find.text('Support queue'), findsNothing);
      expect(find.text('No activity yet'), findsOneWidget);
    });

    testWidgets('staff dashboard adds queue + assigned sections', (t) async {
      await pumpApp(t, const DashboardScreen(),
          auth: FakeAuthRepository(profile: user('it1', 'it_support')), size: desktop);
      expect(find.text('Support queue'), findsOneWidget);
      expect(find.text('Assigned to me'), findsOneWidget);
      expect(find.text('Unassigned'), findsOneWidget);
    });

    testWidgets('desktop uses a navigation rail; phone uses a drawer', (t) async {
      final auth = FakeAuthRepository(profile: user('adm', 'administrator'));
      await pumpApp(t, const AppShell(location: '/dashboard', child: Text('body')),
          auth: auth, size: desktop);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Users'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      await pumpApp(t, const AppShell(location: '/dashboard', child: Text('body')),
          auth: auth, size: phone);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);
    });

    testWidgets('navigation and sign-out are exposed to screen readers (desktop and phone)', (t) async {
      final handle = t.ensureSemantics();
      final auth = FakeAuthRepository(profile: user('adm', 'administrator'));
      await pumpApp(t, const AppShell(location: '/dashboard', child: Text('body')),
          auth: auth, size: desktop);
      for (final s in ['Dashboard', 'My Tickets', 'Support Queue', 'Users', 'Sign out']) {
        expect(find.bySemanticsLabel(RegExp(RegExp.escape(s))), findsWidgets,
            reason: 'desktop: "$s" must be reachable by assistive tech');
      }
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      await pumpApp(t, const AppShell(location: '/dashboard', child: Text('body')),
          auth: auth, size: phone);
      expect(find.bySemanticsLabel(RegExp('Open navigation menu')), findsOneWidget);
      handle.dispose();
    });

    for (final entry in {
      'ticket detail': const TicketDetailScreen(ticketId: '1'),
      'dashboard': const DashboardScreen(),
      'create ticket': const CreateTicketScreen(),
      'my tickets': const MyTicketsScreen(),
    }.entries) {
      testWidgets('no overflow on a 320px-wide phone: ${entry.key}', (t) async {
        final repo = FakeTicketRepository(tickets: [ticket('1', assignedToId: 'it1')]);
        await pumpApp(t, entry.value,
            auth: FakeAuthRepository(profile: user('it1', 'it_support')), tickets: repo,
            size: const Size(320, 640));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });
    }
  });
}
