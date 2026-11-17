import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itsr_radiant/models/user_model.dart';
import 'package:itsr_radiant/providers/auth_provider.dart';
import 'package:itsr_radiant/providers/tickets_provider.dart';
import 'package:itsr_radiant/router/app_router.dart';
import 'package:itsr_radiant/widgets/app_shell.dart';
import 'package:itsr_radiant/widgets/employee_shell.dart';

import '../support/fakes.dart';

void main() {
  group('appRedirect (role-based routing)', () {
    final emp = AsyncData<UserModel?>(user('emp1', 'employee'));
    final it = AsyncData<UserModel?>(user('it1', 'it_support'));
    final adm = AsyncData<UserModel?>(user('adm1', 'administrator'));
    const out = AsyncData<UserModel?>(null);
    String? go(AsyncValue<UserModel?> a, String loc) =>
        appRedirect(a, Uri.parse(loc));

    test('loading session waits on splash and remembers target', () {
      expect(
        go(const AsyncLoading(), '/tickets/abc'),
        '/splash?from=%2Ftickets%2Fabc',
      );
      expect(go(const AsyncLoading(), '/splash'), isNull);
    });

    test(
      'profile-load errors stay on splash for retry instead of logging out',
      () {
        final failed = AsyncError<UserModel?>(
          Exception('offline'),
          StackTrace.current,
        );
        expect(go(failed, '/dashboard'), '/splash');
        expect(go(failed, '/splash'), isNull);
      },
    );

    test('signed-out users are sent to login (deep link kept)', () {
      expect(go(out, '/dashboard'), '/login');
      expect(go(out, '/tickets/abc'), '/login?from=%2Ftickets%2Fabc');
      expect(go(out, '/login'), isNull);
      expect(
        go(out, '/splash?from=%2Ftickets%2Fabc'),
        '/login?from=%2Ftickets%2Fabc',
      );
    });

    test('signed-in users leave login for dashboard or deep link', () {
      expect(go(emp, '/login'), '/dashboard');
      expect(go(emp, '/login?from=%2Ftickets%2Fabc'), '/tickets/abc');
      expect(go(emp, '/login?from=https%3A%2F%2Fevil.test'), '/dashboard');
      expect(go(emp, '/login?from=%2F%2Fevil.test'), '/dashboard');
    });

    test('employees cannot open staff or admin areas', () {
      expect(go(emp, '/queue'), '/dashboard');
      expect(go(emp, '/admin/users'), '/dashboard');
      expect(go(emp, '/login?from=%2Fadmin%2Fusers'), '/dashboard');
      expect(go(emp, '/tickets'), isNull);
      expect(go(emp, '/notifications'), isNull);
      expect(go(emp, '/profile'), isNull);
      expect(go(emp, '/summary'), isNull);
    });

    test('IT support gets the queue but not admin', () {
      expect(go(it, '/queue'), isNull);
      expect(go(it, '/admin/settings'), '/dashboard');
    });

    test('administrators can open everything', () {
      expect(go(adm, '/queue'), isNull);
      expect(go(adm, '/admin/users'), isNull);
    });
  });

  group('navigation items by role', () {
    List<String> paths(String role) =>
        navItemsFor(user('x', role)).map((e) => e.path).toList();
    test(
      'employee',
      () =>
          expect(paths('employee'), ['/dashboard', '/tickets', '/tickets/new']),
    );
    test('it_support', () => expect(paths('it_support'), contains('/queue')));
    test(
      'admin',
      () => expect(
        paths('administrator'),
        containsAll(['/queue', '/admin/users', '/admin/settings']),
      ),
    );
    test('selected index prefers the longest match', () {
      final items = navItemsFor(user('x', 'employee'));
      expect(
        items[selectedNavIndex(items, '/tickets/new')].path,
        '/tickets/new',
      );
      expect(items[selectedNavIndex(items, '/tickets/123')].path, '/tickets');
    });
    test('employee-specific shell restores the employee destinations', () {
      expect(EmployeeShell.tabs.map((e) => e.$1).toList(), [
        '/dashboard',
        '/tickets',
        '/tickets/new',
        '/notifications',
        '/profile',
      ]);
      expect(EmployeeShell.showsNav('/dashboard'), isTrue);
      expect(EmployeeShell.showsNav('/tickets/123'), isFalse);
    });
  });

  group('TicketListNotifier', () {
    late FakeTicketRepository repo;
    late ProviderContainer c;

    setUp(() {
      repo = FakeTicketRepository(
        tickets: [
          for (var i = 1; i <= 45; i++)
            ticket(
              '$i',
              status: i.isEven ? 'open' : 'resolved',
              subject: 'Issue $i',
            ),
          ticket('99', reporterId: 'someone-else'),
        ],
      );
      c = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(profile: user('emp1', 'employee')),
          ),
          ticketRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
    });

    Future<TicketListState> load() async {
      final sub = c.listen(ticketListProvider(TicketScope.mine), (_, _) {});
      addTearDown(sub.close);
      return c.read(ticketListProvider(TicketScope.mine).future);
    }

    test('loads first page once (no refetch loop)', () async {
      final s = await load();
      expect(s.items, hasLength(TicketListNotifier.pageSize));
      expect(s.total, 45);
      expect(repo.fetches, hasLength(1));
    });

    test('loadMore appends next page until exhausted', () async {
      await load();
      final n = c.read(ticketListProvider(TicketScope.mine).notifier);
      await n.loadMore();
      await n.loadMore();
      final s = c.read(ticketListProvider(TicketScope.mine)).value!;
      expect(s.items, hasLength(45));
      expect(s.hasMore, isFalse);
      await n.loadMore();
      expect(
        repo.fetches,
        hasLength(3),
        reason: 'no request once everything is loaded',
      );
    });

    test('setFilter reloads once and identical filter is ignored', () async {
      await load();
      final n = c.read(ticketListProvider(TicketScope.mine).notifier);
      await n.setFilter(const TicketFilter(status: 'open'));
      await n.setFilter(const TicketFilter(status: 'open'));
      final s = c.read(ticketListProvider(TicketScope.mine)).value!;
      expect(s.total, 22);
      expect(s.items.every((t) => t.status == 'open'), isTrue);
      expect(repo.fetches, hasLength(2));
    });

    test('status groups can filter multiple ticket states', () async {
      final groupedRepo = FakeTicketRepository(
        tickets: [
          ticket('open', status: 'open'),
          ticket('reopened', status: 'reopened'),
          ticket('working', status: 'in_progress'),
        ],
      );
      final grouped = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(profile: user('emp1', 'employee')),
          ),
          ticketRepositoryProvider.overrideWithValue(groupedRepo),
        ],
      );
      addTearDown(grouped.dispose);
      final sub = grouped.listen(
        ticketListProvider(TicketScope.mine),
        (_, _) {},
      );
      addTearDown(sub.close);
      await grouped.read(ticketListProvider(TicketScope.mine).future);
      await grouped
          .read(ticketListProvider(TicketScope.mine).notifier)
          .setFilter(const TicketFilter(statusIn: ['open', 'reopened']));
      final state = grouped.read(ticketListProvider(TicketScope.mine)).value!;
      expect(state.items.map((t) => t.status), ['open', 'reopened']);
      expect(state.total, 2);
    });

    test('a stale response cannot overwrite a newer filter', () async {
      await load();
      final n = c.read(ticketListProvider(TicketScope.mine).notifier);
      final gate = repo.searchGate = Completer<void>();
      final slow = n.setFilter(const TicketFilter(search: 'Issue 1')); // stalls
      await n.setFilter(
        const TicketFilter(status: 'resolved'),
      ); // completes first
      gate.complete(); // the older request now returns late
      await slow;
      final s = c.read(ticketListProvider(TicketScope.mine)).value!;
      expect(s.filter.status, 'resolved');
      expect(s.items.every((t) => t.status == 'resolved'), isTrue);
    });
  });

  group('TicketActions', () {
    test(
      'create/accept/resolve call the repository and kick notifications',
      () async {
        final repo = FakeTicketRepository(tickets: [ticket('1')]);
        final c = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository(profile: user('it1', 'it_support')),
            ),
            ticketRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(c.dispose);
        final a = c.read(ticketActionsProvider);
        final id = await a.createTicket(
          subject: 'VPN',
          description: 'down down',
          category: 'Network',
          priority: 'high',
        );
        await a.acceptTicket('1');
        await a.changeStatus('1', 'resolved', resolution: 'Restarted VPN');
        await a.changeStatus('1', 'open');
        expect(id, 'new-id');
        expect(repo.calls, [
          'create:it1:VPN:Network:high',
          'kick',
          'update:1:status=null:assignee=it1:unassign=false:resolution=null',
          'kick',
          'update:1:status=resolved:assignee=null:unassign=false:resolution=Restarted VPN',
          'kick',
          'update:1:status=open:assignee=null:unassign=true:resolution=null',
          'kick',
        ]);
      },
    );
  });
}
