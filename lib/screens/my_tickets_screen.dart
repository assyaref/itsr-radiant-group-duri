import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
import '../providers/tickets_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/ticket_list_view.dart';
import 'employee/employee_tickets_screen.dart';

class MyTicketsScreen extends ConsumerWidget {
  const MyTicketsScreen({super.key});

  // Tab -> status filter
  static const _tabFilters = <int, String?>{
    0: null, // Semua
    1: AppConstants.statusInProgress, // Diproses
    2: AppConstants.statusResolved, // Selesai
  };

  static const _tabLabels = <String>['Semua', 'Diproses', 'Selesai'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    // Employees get the "Tampilan Karyawan" list (search, filter, status chips).
    if (user != null && !user.isStaff) return const EmployeeTicketsScreen();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Daftar Tiket'),
          centerTitle: false,
          elevation: 0,
          bottom: TabBar(
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.muted,
            indicatorColor: AppTheme.primary,
            tabs: const [
              Tab(text: 'Semua'),
              Tab(text: 'Diproses'),
              Tab(text: 'Selesai'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'new_ticket_fab',
          onPressed: () => context.go('/tickets/new'),
          icon: const Icon(Icons.add),
          label: const Text('New ticket'),
        ),
        body: TabBarView(
          children: [
            for (final i in [0, 1, 2])
              Consumer(
                builder: (context, ref, child) {
                  final status = _tabFilters[i];
                  // Apply the filter when the tab index changes.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    ref
                        .read(ticketListProvider(TicketScope.mine).notifier)
                        .setFilter(TicketFilter(status: status));
                  });
                  return _TabContent(
                    scope: TicketScope.mine,
                    emptyTitle: i == 0
                        ? 'You have not submitted any tickets'
                        : 'No ${_tabLabels[i]} tickets',
                    emptyMessage: i == 0
                        ? 'Having an IT problem? Create a ticket and IT Support will be notified.'
                        : 'Try clearing the filters.',
                    emptyAction: i == 0
                        ? FilledButton.icon(
                            onPressed: () => context.go('/tickets/new'),
                            icon: const Icon(Icons.add),
                            label: const Text('Create a ticket'),
                          )
                        : null,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Tab content.
class _TabContent extends ConsumerWidget {
  const _TabContent({
    required this.scope,
    required this.emptyTitle,
    required this.emptyMessage,
    this.emptyAction,
  });
  final TicketScope scope;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget? emptyAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TicketListView(
      scope: scope,
      emptyTitle: emptyTitle,
      emptyMessage: emptyMessage,
      emptyAction: emptyAction,
    );
  }
}
