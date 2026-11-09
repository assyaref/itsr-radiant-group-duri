import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itsr_radiant/providers/auth_provider.dart';
import 'package:itsr_radiant/router/app_router.dart';

import '../support/fakes.dart';

/// The shell mounted through the REAL router (ShellRoute), as in main.dart.
/// Regression for the Phase 16 browser finding: the desktop sidebar (navigation
/// + Sign out) was absent from the accessibility tree.
Future<void> pumpRouted(WidgetTester t, Size size, String role) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(FakeAuthRepository(profile: user('u1', role))),
    ticketRepositoryProvider.overrideWithValue(FakeTicketRepository()),
    adminRepositoryProvider.overrideWithValue(FakeAdminRepository()),
  ]);
  addTearDown(container.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(builder: (_, ref, _) => MaterialApp.router(routerConfig: ref.watch(goRouterProvider))),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('desktop (routed): navigation and Sign out are in the semantics tree', (t) async {
    final handle = t.ensureSemantics();
    await pumpRouted(t, const Size(1440, 900), 'administrator');
    expect(find.text('Sign out'), findsOneWidget); // painted
    for (final s in ['My Tickets', 'Support Queue', 'Users', 'Settings', 'Sign out']) {
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(s))), findsWidgets,
          reason: '"$s" must be reachable by assistive tech');
    }
    handle.dispose();
  });

  testWidgets('phone (routed): menu button is in the semantics tree', (t) async {
    final handle = t.ensureSemantics();
    await pumpRouted(t, const Size(390, 844), 'employee');
    expect(find.bySemanticsLabel(RegExp('Open navigation menu')), findsOneWidget);
    handle.dispose();
  });
}
