import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../screens/admin/categories_screen.dart';
import '../screens/admin/settings_screen.dart';
import '../screens/admin/users_screen.dart';
import '../screens/create_ticket_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/it_support_queue_screen.dart';
import '../screens/login_screen.dart';
import '../screens/my_tickets_screen.dart';
import '../screens/ticket_detail_screen.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';

/// Pure redirect logic (unit-tested). Returns the location to go to, or null.
///
/// * session still loading      -> /splash (remembering the target)
/// * signed out                 -> /login  (remembering the target)
/// * signed in on /login|splash -> target or /dashboard
/// * staff-only / admin-only    -> /dashboard when the role does not allow it
String? appRedirect(AsyncValue<UserModel?> auth, Uri uri) {
  final path = uri.path;
  final from = uri.queryParameters['from'];
  final isPublic = path == '/login' || path == '/splash';
  String withFrom(String target) {
    if (isPublic) return from == null ? target : '$target?from=${Uri.encodeComponent(from)}';
    if (path == '/' || path == '/dashboard') return target;
    return '$target?from=${Uri.encodeComponent(uri.toString())}';
  }

  if (auth.isLoading && !auth.hasValue) {
    return path == '/splash' ? null : withFrom('/splash');
  }

  final user = auth.valueOrNull;
  if (user == null) {
    return path == '/login' ? null : withFrom('/login');
  }

  if (isPublic || path == '/') {
    final target = (from != null && from.startsWith('/') && !from.startsWith('//'))
        ? from
        : '/dashboard';
    final allowed = appRedirect(auth, Uri.parse(target));
    return allowed ?? target;
  }
  if (path.startsWith('/queue') && !user.isStaff) return '/dashboard';
  if (path.startsWith('/admin') && !user.isAdmin) return '/dashboard';
  return null;
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<AsyncValue<UserModel?>>(const AsyncLoading());
  ref.listen<AsyncValue<UserModel?>>(
    currentUserProvider,
    (_, next) => auth.value = next,
    fireImmediately: true,
  );
  ref.onDispose(auth.dispose);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: auth,
    redirect: (context, state) => appRedirect(auth.value, state.uri),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => const Scaffold(body: LoadingView(label: 'Loading…')),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/', redirect: (_, _) => '/dashboard'),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
          GoRoute(path: '/tickets', builder: (_, _) => const MyTicketsScreen()),
          GoRoute(path: '/tickets/new', builder: (_, _) => const CreateTicketScreen()),
          GoRoute(
            path: '/tickets/:id',
            builder: (_, state) => TicketDetailScreen(ticketId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/queue', builder: (_, _) => const ITSupportQueueScreen()),
          GoRoute(path: '/admin/users', builder: (_, _) => const UsersScreen()),
          GoRoute(path: '/admin/categories', builder: (_, _) => const CategoriesScreen()),
          GoRoute(path: '/admin/settings', builder: (_, _) => const SettingsScreen()),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: EmptyView(
        icon: Icons.search_off,
        title: 'Page not found',
        action: FilledButton(
          onPressed: () => context.go('/dashboard'),
          child: const Text('Go to dashboard'),
        ),
      ),
    ),
  );
});
