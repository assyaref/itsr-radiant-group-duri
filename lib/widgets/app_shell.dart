import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../utils/formatters.dart';
import 'common.dart';
import 'employee_ui.dart';

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
    Icons.home_outlined,
    Icons.home_rounded,
  ),
  const NavItem(
    '/tickets',
    'Tiket Saya',
    Icons.receipt_long_outlined,
    Icons.receipt_long,
  ),
  const NavItem(
    '/tickets/new',
    'Buat Tiket',
    Icons.add_box_outlined,
    Icons.add_box,
  ),
  if (user?.isStaff ?? false) ...const [
    NavItem(
      '/queue',
      'Manajemen Tiket',
      Icons.assignment_outlined,
      Icons.assignment,
    ),
  ],
  if (user?.isAdmin ?? false) ...const [
    NavItem('/admin/users', 'Karyawan', Icons.badge_outlined, Icons.badge),
    NavItem(
      '/admin/categories',
      'Kategori',
      Icons.category_outlined,
      Icons.category,
    ),
  ],
  if (user?.isStaff ?? false)
    const NavItem(
      '/summary',
      'Laporan',
      Icons.insert_chart_outlined,
      Icons.insert_chart,
    ),
  if (user?.isAdmin ?? false)
    const NavItem(
      '/admin/settings',
      'Pengaturan',
      Icons.settings_outlined,
      Icons.settings,
    ),
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
  if (best == -1 && location.startsWith('/admin/email')) {
    best = items.indexWhere((e) => e.path == '/admin/settings');
  }
  return best < 0 ? 0 : best;
}

const Color _navy = Color(0xFF0B1A3A);
const Color _navyLine = Color(0xFF1E2D52);

Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final ok = await showConfirmDialog(
    context,
    title: 'Keluar',
    message: 'Keluar dari aplikasi?',
    confirmLabel: 'Keluar',
  );
  if (ok) await ref.read(authControllerProvider.notifier).signOut();
}

/// Shell for IT Support and administrators ("Dashboard Administrator" design):
/// desktop = navy sidebar + top bar with search / notifications / avatar;
/// phone = bottom navigation (Beranda · Tiket · + · Notifikasi · Menu).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final items = navItemsFor(user);
    final selected = selectedNavIndex(items, location);

    if (isDesktop(context)) {
      return Scaffold(
        backgroundColor: EColors.page,
        body: Row(
          children: [
            SizedBox(
              key: const Key('desktop_sidebar'),
              width: 240,
              child: _Sidebar(items: items, selected: selected, user: user),
            ),
            Expanded(
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: Column(
                  children: [
                    _TopBar(user: user),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: EColors.page,
      body: child,
      bottomNavigationBar: _StaffBottomNav(
        location: location,
        items: items,
        user: user,
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.items,
    required this.selected,
    required this.user,
  });
  final List<NavItem> items;
  final int selected;
  final UserModel? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: _navy,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 16, 18),
              child: Row(
                children: [
                  const Icon(
                    Icons.headset_mic_rounded,
                    color: Color(0xFF60A5FA),
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'IT Support',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Cabang Duri',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
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
            const Divider(height: 1, color: _navyLine),
            _UserCard(user: user),
          ],
        ),
      ),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Material(
      color: selected ? EColors.blue : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                selected ? item.selectedIcon : item.icon,
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.75),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.88),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.user});
  final UserModel? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = user?.fullName ?? '';
    return Semantics(
      button: true,
      label: 'Akun',
      child: PopupMenuButton<String>(
        tooltip: 'Akun',
        position: PopupMenuPosition.over,
        offset: const Offset(0, -110),
        onSelected: (v) {
          if (v == 'profile') context.go('/profile');
          if (v == 'signout') confirmSignOut(context, ref);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'profile',
            child: ListTile(
              leading: Icon(Icons.person_outline),
              title: Text('Profil'),
            ),
          ),
          PopupMenuItem(
            value: 'signout',
            child: ListTile(
              leading: Icon(Icons.logout, color: EColors.red),
              title: Text('Keluar', style: TextStyle(color: EColors.red)),
            ),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
          child: Row(
            children: [
              InitialsAvatar(name, size: 38, solid: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      Fmt.role(user?.role),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Desktop top bar: global ticket search, notifications, avatar.
class _TopBar extends ConsumerStatefulWidget {
  const _TopBar({required this.user});
  final UserModel? user;

  @override
  ConsumerState<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<_TopBar> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _submit(String v) {
    final q = v.trim();
    final staff = widget.user?.isStaff ?? false;
    final base = staff ? '/queue' : '/tickets';
    context.go(q.isEmpty ? base : '$base?q=${Uri.encodeQueryComponent(q)}');
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.user?.fullName ?? '';
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: EColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: TextField(
                  key: const Key('global_search'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _submit,
                  decoration: eInput(
                    hint: 'Cari tiket (nomor, judul, deskripsi)…',
                    prefix: const Icon(Icons.search, color: EColors.muted),
                  ).copyWith(fillColor: const Color(0xFFF1F5F9), filled: true),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            tooltip: 'Notifikasi',
            onPressed: () => context.go('/notifications'),
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: EColors.text,
            ),
          ),
          const SizedBox(width: 8),
          InitialsAvatar(name, size: 38, onTap: () => context.go('/profile')),
        ],
      ),
    );
  }
}

class _StaffBottomNav extends ConsumerWidget {
  const _StaffBottomNav({
    required this.location,
    required this.items,
    required this.user,
  });
  final String location;
  final List<NavItem> items;
  final UserModel? user;

  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: InitialsAvatar(user?.fullName ?? '', size: 40),
                title: Text(
                  user?.fullName ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(Fmt.role(user?.role)),
              ),
              const Divider(),
              for (final it in items)
                ListTile(
                  leading: Icon(it.icon, color: EColors.text),
                  title: Text(it.label),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.go(it.path);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.person_outline, color: EColors.text),
                title: const Text('Profil'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.go('/profile');
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: EColors.red),
                title: const Text(
                  'Keluar',
                  style: TextStyle(color: EColors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  confirmSignOut(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget tab(
      String path,
      String label,
      IconData icon,
      IconData active, {
      VoidCallback? onTap,
    }) {
      final sel =
          onTap == null &&
          (location == path ||
              (path != '/dashboard' && location.startsWith('$path/')));
      final color = sel ? EColors.blue : EColors.muted;
      return Expanded(
        child: Semantics(
          button: true,
          selected: sel,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap ?? () => context.go(path),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(sel ? active : icon, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final staff = user?.isStaff ?? false;
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
              tab(
                '/dashboard',
                'Beranda',
                Icons.home_outlined,
                Icons.home_rounded,
              ),
              tab(
                staff ? '/queue' : '/tickets',
                'Tiket',
                Icons.receipt_long_outlined,
                Icons.receipt_long,
              ),
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Buat Tiket',
                  excludeSemantics: true,
                  child: InkWell(
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
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Buat Tiket',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: EColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              tab(
                '/notifications',
                'Notifikasi',
                Icons.notifications_none_rounded,
                Icons.notifications_rounded,
              ),
              tab(
                '',
                'Menu',
                Icons.menu_rounded,
                Icons.menu_rounded,
                onTap: () => _openMenu(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
