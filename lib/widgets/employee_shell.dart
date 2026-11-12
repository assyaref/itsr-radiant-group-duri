import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'employee_ui.dart';

/// Frame for every employee screen.
///
/// The same phone-style layout is used on every screen size: on a desktop the
/// app is a centred column (max [maxWidth]) on a soft background, so employees
/// see exactly the design on both. The bottom navigation (Beranda · Tiket ·
/// + Buat Tiket · Notifikasi · Profil) shows on the four main pages; create /
/// detail / confirmation pages have their own back arrow instead.
class EmployeeShell extends StatelessWidget {
  const EmployeeShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  static const maxWidth = 480.0;

  static const tabs = [
    ('/dashboard', 'Beranda', Icons.home_outlined, Icons.home_rounded),
    ('/tickets', 'Tiket', Icons.receipt_long_outlined, Icons.receipt_long),
    ('/tickets/new', 'Buat Tiket', Icons.add, Icons.add),
    (
      '/notifications',
      'Notifikasi',
      Icons.notifications_none_rounded,
      Icons.notifications_rounded,
    ),
    ('/profile', 'Profil', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  /// Whether [location] is one of the main pages that show the bottom bar.
  static bool showsNav(String location) =>
      location == '/dashboard' ||
      location == '/tickets' ||
      location == '/notifications' ||
      location == '/profile';

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > maxWidth + 32;
    final page = Scaffold(
      backgroundColor: EColors.page,
      body: child,
      bottomNavigationBar: showsNav(location)
          ? _BottomNav(location: location)
          : null,
    );
    if (!wide) return page;
    return ColoredBox(
      color: const Color(0xFFE8EEF8),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          decoration: const BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Color(0x1A0F172A),
                blurRadius: 32,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRect(child: page),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.location});
  final String location;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: EColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (final (path, label, icon, activeIcon) in EmployeeShell.tabs)
                Expanded(
                  child: path == '/tickets/new'
                      ? _CreateButton(label: label)
                      : _NavItem(
                          label: label,
                          icon: location == path ? activeIcon : icon,
                          active: location == path,
                          onTap: () => context.go(path),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? EColors.blue : EColors.muted;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      key: const Key('nav_create_ticket'),
      onTap: () => context.push('/tickets/new'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: EColors.blue,
              boxShadow: [
                BoxShadow(
                  color: Color(0x552563EB),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: EColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}
