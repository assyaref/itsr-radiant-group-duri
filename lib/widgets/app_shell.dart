import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../utils/formatters.dart';
import 'common.dart';

class NavItem {
  const NavItem(this.path, this.label, this.icon, this.selectedIcon);
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Navigation entries visible for a role. Server-side RLS is the real guard;
/// this only hides links a user cannot use.
List<NavItem> navItemsFor(UserModel? user) => [
      const NavItem('/dashboard', 'Dashboard', Icons.dashboard_outlined, Icons.dashboard),
      const NavItem('/tickets', 'My Tickets', Icons.confirmation_number_outlined,
          Icons.confirmation_number),
      const NavItem('/tickets/new', 'New Ticket', Icons.add_circle_outline, Icons.add_circle),
      if (user?.isStaff ?? false)
        const NavItem('/queue', 'Support Queue', Icons.support_agent_outlined, Icons.support_agent),
      if (user?.isAdmin ?? false) ...const [
        NavItem('/admin/users', 'Users', Icons.people_outline, Icons.people),
        NavItem('/admin/categories', 'Categories', Icons.category_outlined, Icons.category),
        NavItem('/admin/settings', 'Settings', Icons.settings_outlined, Icons.settings),
        NavItem(
          '/admin/email-notifications',
          'Email & Notifications',
          Icons.email_outlined,
          Icons.email,
        ),
      ],
    ];

int selectedNavIndex(List<NavItem> items, String location) {
  var best = -1, bestLen = -1;
  for (var i = 0; i < items.length; i++) {
    final p = items[i].path;
    final match = location == p || location.startsWith('$p/');
    if (match && p.length > bestLen) {
      best = i;
      bestLen = p.length;
    }
  }
  // Ticket detail pages belong to "My Tickets" unless a longer match exists.
  if (best == -1 && location.startsWith('/tickets/')) {
    best = items.indexWhere((e) => e.path == '/tickets');
  }
  return best < 0 ? 0 : best;
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(context,
        title: 'Sign out', message: 'Do you want to sign out?', confirmLabel: 'Sign out');
    if (ok) await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final items = navItemsFor(user);
    final selected = selectedNavIndex(items, location);
    final desktop = isDesktop(context);
    final title = items[selected].label;

    final userHeader = ListTile(
      leading: CircleAvatar(
        child: Text((user?.fullName.isNotEmpty ?? false) ? user!.fullName[0].toUpperCase() : '?'),
      ),
      title: Text(user?.fullName ?? '', overflow: TextOverflow.ellipsis),
      subtitle: Text('${user?.employeeNumber ?? ''} • ${Fmt.role(user?.role)}',
          overflow: TextOverflow.ellipsis),
    );

    if (desktop) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 240,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 1,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                        child: Row(children: [
                          Icon(Icons.support_agent, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(AppConstants.appShortName,
                                style: Theme.of(context).textTheme.titleLarge),
                          ),
                        ]),
                      ),
                      userHeader,
                      const Divider(),
                      Expanded(
                        child: NavigationRail(
                          extended: true,
                          minExtendedWidth: 240,
                          selectedIndex: selected,
                          onDestinationSelected: (i) => context.go(items[i].path),
                          destinations: [
                            for (final it in items)
                              NavigationRailDestination(
                                icon: Icon(it.icon),
                                selectedIcon: Icon(it.selectedIcon),
                                label: Text(it.label),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.logout),
                        title: const Text('Sign out'),
                        onTap: () => _signOut(context, ref),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              // Own semantics container: the nested (ShellRoute) Navigator paints
              // a ModalBarrier whose BlockSemantics would otherwise drop the
              // sidebar (navigation + Sign out) from the accessibility tree.
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: Scaffold(
                  appBar: AppBar(title: Text(title)),
                  body: child,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              userHeader,
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      ListTile(
                        leading: Icon(i == selected ? items[i].selectedIcon : items[i].icon),
                        title: Text(items[i].label),
                        selected: i == selected,
                        onTap: () {
                          Navigator.pop(context);
                          context.go(items[i].path);
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () {
                  Navigator.pop(context);
                  _signOut(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
      body: child,
    );
  }
}
