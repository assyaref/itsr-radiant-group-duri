import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../utils/formatters.dart';
import 'common.dart';

/// Sidebar groups, in display order.
enum NavSection {
  main('Main'),
  support('IT Support'),
  management('Management'),
  system('System');

  const NavSection(this.label);
  final String label;
}

class NavItem {
  const NavItem(
    this.path,
    this.label,
    this.icon,
    this.selectedIcon, {
    this.section = NavSection.main,
  });
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final NavSection section;
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
      section: NavSection.support,
    ),
    NavItem(
      '/summary',
      'Ticket Summary',
      Icons.insert_chart_outlined,
      Icons.insert_chart,
      section: NavSection.support,
    ),
  ],
  if (user?.isAdmin ?? false) ...const [
    NavItem(
      '/admin/users',
      'Users',
      Icons.people_outline,
      Icons.people,
      section: NavSection.management,
    ),
    NavItem(
      '/admin/categories',
      'Categories',
      Icons.category_outlined,
      Icons.category,
      section: NavSection.management,
    ),
    NavItem(
      '/admin/settings',
      'Settings',
      Icons.settings_outlined,
      Icons.settings,
      section: NavSection.system,
    ),
    NavItem(
      '/admin/email-notifications',
      'Email & Notifications',
      Icons.email_outlined,
      Icons.email,
      section: NavSection.system,
    ),
    NavItem(
      '/admin/data',
      'Backup & Data',
      Icons.backup_outlined,
      Icons.backup,
      section: NavSection.system,
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

/// Whether the desktop sidebar is collapsed to an icon rail.
final sidebarCollapsedProvider = StateProvider<bool>((_) => false);

const Color _sidebarBg = Color(0xFF0F172A);
const Color _sidebarBgAlt = Color(0xFF111C33);
const Color _sidebarLine = Color(0xFF1E293B);
const Color _sidebarHover = Color(0xFF1E293B);
const Color _sidebarText = Color(0xFFCBD5E1);
const Color _sidebarMuted = Color(0xFF64748B);
const Color _accent = Color(0xFF60A5FA);

const double _expandedWidth = 264;
const double _collapsedWidth = 76;

Color _roleColor(String? role) => switch (role) {
  'administrator' || 'superadmin' => const Color(0xFFF59E0B),
  'it_support' => const Color(0xFF34D399),
  _ => _accent,
};

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
    final current = items[selected];

    final appBar = AppBar(
      titleSpacing: desktop ? 24 : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (items.any((e) => e.section != NavSection.main))
            ExcludeSemantics(
              child: Text(
                current.section.label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.muted,
                ),
              ),
            ),
          Text(current.label),
        ],
      ),
      backgroundColor: Colors.white,
      foregroundColor: AppTheme.ink,
      surfaceTintColor: Colors.white,
      elevation: 0,
      shape: const Border(bottom: BorderSide(color: AppTheme.border)),
    );

    if (desktop) {
      final collapsed = ref.watch(sidebarCollapsedProvider);
      return Scaffold(
        body: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: collapsed ? _collapsedWidth : _expandedWidth,
              child: _Sidebar(
                user: user,
                items: items,
                selected: selected,
                collapsed: collapsed,
                onToggle: () =>
                    ref.read(sidebarCollapsedProvider.notifier).state =
                        !collapsed,
                onNavigate: (path) => context.go(path),
                onSignOut: () => _signOut(context, ref),
              ),
            ),
            Expanded(
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: Scaffold(appBar: appBar, body: child),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      drawer: Drawer(
        width: 288,
        backgroundColor: _sidebarBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
        ),
        child: _Sidebar(
          user: user,
          items: items,
          selected: selected,
          collapsed: false,
          onNavigate: (path) {
            Navigator.pop(context);
            context.go(path);
          },
          onSignOut: () {
            Navigator.pop(context);
            _signOut(context, ref);
          },
        ),
      ),
      body: child,
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.user,
    required this.items,
    required this.selected,
    required this.collapsed,
    required this.onNavigate,
    required this.onSignOut,
    this.onToggle,
  });
  final UserModel? user;
  final List<NavItem> items;
  final int selected;
  final bool collapsed;
  final ValueChanged<String> onNavigate;
  final VoidCallback onSignOut;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // While the width animates, render the compact layout until the full
    // layout actually fits — avoids overflow mid-transition.
    builder: (context, c) => _build(collapsed || c.maxWidth < 220),
  );

  Widget _build(bool collapsed) {
    final children = <Widget>[];
    NavSection? lastSection;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.section != lastSection) {
        children.add(
          _SectionHeader(
            label: item.section.label,
            collapsed: collapsed,
            first: lastSection == null,
          ),
        );
        lastSection = item.section;
      }
      children.add(
        _NavTile(
          item: item,
          selected: i == selected,
          collapsed: collapsed,
          onTap: () => onNavigate(item.path),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_sidebarBg, _sidebarBgAlt],
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Brand(collapsed: collapsed, onToggle: onToggle),
            const Divider(height: 1, color: _sidebarLine),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                children: children,
              ),
            ),
            const Divider(height: 1, color: _sidebarLine),
            _UserCard(user: user, collapsed: collapsed),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _SidebarButton(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                collapsed: collapsed,
                color: const Color(0xFFFCA5A5),
                onTap: onSignOut,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed, this.onToggle});
  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(Icons.support_agent, color: Colors.white, size: 22),
    );

    final toggle = onToggle == null
        ? null
        : IconButton(
            tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
            onPressed: onToggle,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              collapsed
                  ? Icons.keyboard_double_arrow_right_rounded
                  : Icons.keyboard_double_arrow_left_rounded,
              color: _sidebarMuted,
              size: 20,
            ),
          );

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            logo,
            if (toggle != null) ...[const SizedBox(height: 6), toggle],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
      child: Row(
        children: [
          logo,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  AppConstants.appShortName,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'IT Support Cabang Duri',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          ?toggle,
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.collapsed,
    required this.first,
  });
  final String label;
  final bool collapsed;
  final bool first;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return first
          ? const SizedBox(height: 4)
          : const Padding(
              padding: EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              child: Divider(height: 1, color: _sidebarLine),
            );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(12, first ? 6 : 14, 12, 6),
      child: ExcludeSemantics(
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: _sidebarMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });
  final NavItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    final item = widget.item;
    final fg = active || _hover ? Colors.white : _sidebarText;
    final bg = active
        ? AppTheme.primary.withValues(alpha: 0.22)
        : (_hover ? _sidebarHover : Colors.transparent);

    Widget tile = Semantics(
      button: true,
      selected: active,
      label: widget.collapsed ? item.label : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 40,
            margin: const EdgeInsets.symmetric(vertical: 1.5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: widget.collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (!widget.collapsed)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 3,
                    height: active ? 22 : 0,
                    margin: const EdgeInsets.only(right: 11),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                Icon(
                  active ? item.selectedIcon : item.icon,
                  color: active ? _accent : fg,
                  size: 20,
                ),
                if (!widget.collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.collapsed) {
      tile = Tooltip(
        message: item.label,
        excludeFromSemantics: true,
        child: tile,
      );
    }
    return tile;
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.collapsed});
  final UserModel? user;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final name = user?.fullName ?? '';
    final roleColor = _roleColor(user?.role);
    final avatar = Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: roleColor.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: roleColor.withValues(alpha: 0.6)),
      ),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: roleColor,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Tooltip(
            message: '$name • ${Fmt.role(user?.role)}',
            child: avatar,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: roleColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          Fmt.role(user?.role),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: roleColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        user?.employeeNumber ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _sidebarMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatefulWidget {
  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool collapsed;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<_SidebarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Widget button = Semantics(
      button: true,
      label: widget.collapsed ? widget.label : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 42,
            decoration: BoxDecoration(
              color: _hover
                  ? widget.color.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: widget.color.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: widget.color, size: 18),
                if (!widget.collapsed) ...[
                  const SizedBox(width: 10),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.color,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.collapsed) {
      button = Tooltip(
        message: widget.label,
        excludeFromSemantics: true,
        child: button,
      );
    }
    return button;
  }
}
