import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../widgets/common.dart';
import 'admin/admin_dashboard_screen.dart';
import 'employee/employee_home_screen.dart';

/// /dashboard: employees get "Beranda", IT Support and administrators the
/// "Dashboard Administrator" design.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) return const LoadingView();
    if (!user.isStaff) return EmployeeHomeScreen(user: user);
    return AdminDashboardScreen(user: user);
  }
}
