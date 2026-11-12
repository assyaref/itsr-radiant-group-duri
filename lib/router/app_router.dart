import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../screens/admin/categories_screen.dart';
import '../screens/admin/email_notifications_screen.dart';
import '../screens/admin/settings_screen.dart';
import '../screens/admin/users_screen.dart';
import '../screens/create_ticket_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/employee/notifications_screen.dart';
import '../screens/employee/profile_screen.dart';
import '../screens/employee/ticket_submitted_screen.dart';
import '../screens/it_support_queue_screen.dart';
import '../screens/login_screen.dart';
import '../screens/my_tickets_screen.dart';
import '../screens/ticket_detail_screen.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/employee_shell.dart';

/// Pure redirect logic (unit-tested). Returns the location to go to, or null.
///
/// * session still loading      -> /splash (remembering the target)
/// * profile could not be loaded -> /splash, which shows the error with
///   "Try again" / "Sign out" (instead of silently dropping to /login)
/// * signed out                 -> /login  (remembering the target)
/// * signed in on /login|splash -> target or /dashboard
/// * staff-only / admin-only    -> /dashboard when the role does not allow it
String? appRedirect(AsyncValue<UserModel?> auth, Uri uri) {
  final path = uri.path;
  final from = uri.queryParameters['from'];
  final isPublic = path == '/login' || path == '/splash';
  String withFrom(String target) {
    if (isPublic) {
      return from == null
          ? target
          : '$target?from=${Uri.encodeComponent(from)}';
    }
    if (path == '/' || path == '/dashboard') return target;
    return '$target?from=${Uri.encodeComponent(uri.toString())}';
  }

  if (!auth.hasValue && (auth.isLoading || auth.hasError)) {
    return path == '/splash' ? null : withFrom('/splash');
  }

  final user = auth.valueOrNull;
  if (user == null) {
    return path == '/login' ? null : withFrom('/login');
  }

  if (isPublic || path == '/') {
    final target =
        (from != null && from.startsWith('/') && !from.startsWith('//'))
        ? from
        : '/dashboard';
    final allowed = appRedirect(auth, Uri.parse(target));
    return allowed ?? target;
  }
  if (path.startsWith('/queue') && !user.isStaff) return '/dashboard';
  if (path.startsWith('/admin') && !user.isAdmin) return '/dashboard';
  return null;
}

/// Shown while the session/profile loads, and when loading it failed.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(currentUserProvider);
    if (auth.hasError && !auth.hasValue && !auth.isLoading) {
      return Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ErrorView(
              error: auth.error!,
              onRetry: () =>
                  ref.read(authControllerProvider.notifier).retryProfile(),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      );
    }
    return const Scaffold(body: LoadingView(label: 'Loading…'));
  }
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
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/', redirect: (_, _) => '/dashboard'),
      ShellRoute(
        // Employees get the phone-style design on every screen size; IT
        // Support and administrators keep the sidebar shell.
        builder: (context, state, child) => Consumer(
          builder: (context, ref, _) {
            final user = ref.watch(currentUserProvider).valueOrNull;
            return (user != null && !user.isStaff)
                ? EmployeeShell(location: state.uri.path, child: child)
                : AppShell(location: state.uri.path, child: child);
          },
        ),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, _) => const DashboardScreen(),
          ),
          GoRoute(path: '/tickets', builder: (_, _) => const MyTicketsScreen()),
          GoRoute(
            path: '/tickets/new',
            builder: (_, _) => const CreateTicketScreen(),
          ),
          GoRoute(
            path: '/tickets/:id',
            builder: (_, state) =>
                TicketDetailScreen(ticketId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'submitted',
                builder: (_, state) => TicketSubmittedScreen(
                  ticketId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, _) => const NotificationsScreen(),
          ),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(
            path: '/queue',
            builder: (_, _) => const ITSupportQueueScreen(),
          ),
          GoRoute(path: '/admin/users', builder: (_, _) => const UsersScreen()),
          GoRoute(
            path: '/admin/categories',
            builder: (_, _) => const CategoriesScreen(),
          ),
          GoRoute(
            path: '/admin/settings',
            builder: (_, _) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/admin/email-notifications',
            builder: (_, _) => const EmailNotificationsScreen(),
          ),
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
