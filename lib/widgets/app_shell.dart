import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
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
  const NavItem(
    '/dashboard',
    'Dashboard',
    Icons.dashboard_outlined,
    Icons.dashboard,
  ),
  const NavItem(
    '/tickets',
    'My Tickets',
    Icons.confirmation_number_outlined,
    Icons.confirmation_number,
  ),
  const NavItem(
    '/tickets/new',
    'New Ticket',
    Icons.add_circle_outline,
    Icons.add_circle,
  ),
  if (user?.isStaff ?? false) ...const [
    NavItem(
      '/queue',
      'Support Queue',
      Icons.support_agent_outlined,
      Icons.support_agent,
    ),
    NavItem(
      '/summary',
      'Ticket Summary',
      Icons.insert_chart_outlined,
      Icons.insert_chart,
    ),
  ],
  if (user?.isAdmin ?? false) ...const [
    NavItem('/admin/users', 'Users', Icons.people_outline, Icons.people),
    NavItem(
      '/admin/categories',
      'Categories',
      Icons.category_outlined,
      Icons.category,
    ),
    NavItem(
      '/admin/settings',
      'Settings',
      Icons.settings_outlined,
      Icons.settings,
    ),
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
  if (best == -1 && location.startsWith('/tickets/')) {
    best = items.indexWhere((e) => e.path == '/tickets');
  }
  return best < 0 ? 0 : best;
}

const Color _sidebarDark = Color(0xFF0F172A);
const Color _sidebarItemBg = Color(0xFF1E293B);

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Sign out',
      message: 'Do you want to sign out?',
      confirmLabel: 'Sign out',
    );
    if (ok) await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final items = navItemsFor(user);
    final selected = selectedNavIndex(items, location);
    final desktop = isDesktop(context);
    final title = items[selected].label;

    final userHeader = Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.support_agent,
              color: AppTheme.primary,
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppConstants.appShortName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'IT Support Cabang Duri',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              child: Text(
                (user?.fullName.isNotEmpty ?? false)
                    ? user!.fullName[0].toUpperCase()
                    : '?',
              ),
            ),
            title: Text(
              user?.fullName ?? '',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            subtitle: Text(
              '${user?.employeeNumber ?? ''} • ${Fmt.role(user?.role)}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );

    if (desktop) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 250,
              child: Material(
                color: _sidebarDark,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      userHeader,
                      Expanded(
                        child: ListView(
                          children: [
                            for (var i = 0; i < items.length; i++)
                              _NavTile(
                                item: items[i],
                                selected: i == selected,
                                onTap: () => context.go(items[i].path),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFF334155)),
                      ListTile(
                        leading: const Icon(
                          Icons.logout,
                          color: Colors.white70,
                        ),
                        title: const Text(
                          'Sign out',
                          style: TextStyle(color: Colors.white),
                        ),
                        onTap: () => _signOut(context, ref),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(title),
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.ink,
                    elevation: 0,
                  ),
                  body: child,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.ink,
        elevation: 0,
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              userHeader,
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _NavTile(
                        item: items[i],
                        selected: i == selected,
                        onTap: () {
                          Navigator.pop(context);
                          context.go(items[i].path);
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              ListTile(
                leading: const Icon(Icons.logout, color: AppTheme.ink),
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

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = selected;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: active ? _sidebarItemBg : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              active ? item.selectedIcon : item.icon,
              color: active
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.7),
              size: 20,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  color: active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.85),
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
