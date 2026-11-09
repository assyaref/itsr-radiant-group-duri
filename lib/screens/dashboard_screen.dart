import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_theme.dart';
import '../models/activity_model.dart';
import '../models/ticket_stats.dart';
import '../providers/auth_provider.dart';
import '../providers/tickets_provider.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/ticket_list_view.dart';

/// Role-aware dashboard: employees see their own tickets; IT Support and
/// administrators additionally see queue-wide and assigned-to-me figures.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) return const LoadingView();

    Future<void> refresh() async {
      ref.invalidate(ticketStatsProvider);
      ref.invalidate(recentActivityProvider);
      ref.invalidate(ticketListProvider(TicketScope.assignedToMe));
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 12,
                  spacing: 12,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome, ${user.fullName}',
                            style: Theme.of(context).textTheme.titleLarge),
                        Text('${Fmt.role(user.role)} • ${user.department}',
                            style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: () => context.go('/tickets/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('New ticket'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (user.isStaff) ...[
                  const _SectionTitle('Support queue'),
                  _StatsSection(
                    scope: 'all',
                    onTap: () => context.go('/queue'),
                    staff: true,
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('Assigned to me'),
                  const _AssignedToMe(),
                  const SizedBox(height: 20),
                ],
                const _SectionTitle('My tickets'),
                _StatsSection(scope: 'mine', onTap: () => context.go('/tickets')),
                const SizedBox(height: 20),
                const _SectionTitle('Recent activity'),
                const _RecentActivity(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Semantics(
          header: true,
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
      );
}

class _StatsSection extends ConsumerWidget {
  const _StatsSection({required this.scope, this.onTap, this.staff = false});
  final String scope;
  final VoidCallback? onTap;
  final bool staff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(ticketStatsProvider(scope));
    return stats.when(
      loading: () => const SizedBox(height: 90, child: LoadingView()),
      error: (e, _) => ErrorView(
          error: e, onRetry: () => ref.invalidate(ticketStatsProvider(scope))),
      data: (TicketStats s) => StatGrid(children: [
        if (staff)
          StatCard(
              label: 'Unassigned',
              value: s.unassigned,
              icon: Icons.inbox,
              color: Colors.red[600]!,
              onTap: onTap)
        else
          StatCard(
              label: 'Total tickets',
              value: s.total,
              icon: Icons.confirmation_number,
              color: Colors.blueGrey,
              onTap: onTap),
        StatCard(
            label: 'Open',
            value: s.open,
            icon: Icons.mark_email_unread_outlined,
            color: AppTheme.getStatusColor('open'),
            onTap: onTap),
        StatCard(
            label: 'In progress',
            value: s.inProgress,
            icon: Icons.build_circle_outlined,
            color: AppTheme.getStatusColor('in_progress'),
            onTap: onTap),
        StatCard(
            label: 'Resolved',
            value: s.resolved,
            icon: Icons.check_circle_outline,
            color: AppTheme.getStatusColor('resolved'),
            onTap: onTap),
      ]),
    );
  }
}

class _AssignedToMe extends ConsumerWidget {
  const _AssignedToMe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(ticketListProvider(TicketScope.assignedToMe));
    return list.when(
      loading: () => const SizedBox(height: 80, child: LoadingView()),
      error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(ticketListProvider(TicketScope.assignedToMe))),
      data: (s) {
        final active = s.items.where((t) => !t.isFinished).take(5).toList();
        if (active.isEmpty) {
          return const Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.task_alt),
              title: Text('Nothing assigned to you right now'),
            ),
          );
        }
        return Column(children: [
          for (final t in active)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TicketTile(ticket: t, showReporter: true),
            ),
        ]);
      },
    );
  }
}

class _RecentActivity extends ConsumerWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(recentActivityProvider);
    return activity.when(
      loading: () => const SizedBox(height: 80, child: LoadingView()),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.invalidate(recentActivityProvider)),
      data: (items) {
        if (items.isEmpty) {
          return const Card(
            margin: EdgeInsets.zero,
            child: EmptyView(
              icon: Icons.history,
              title: 'No activity yet',
              message: 'Updates on your tickets will appear here.',
            ),
          );
        }
        return Card(
          margin: EdgeInsets.zero,
          child: Column(children: [
            for (final a in items)
              ListTile(
                leading: Icon(activityIcon(a.action), color: activityColor(a.action)),
                title: Text(
                  '${a.ticketNumber ?? ''} ${describeActivity(a)}'.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if (a.ticketSubject != null) a.ticketSubject!,
                    Fmt.relative(a.createdAt),
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => context.push('/tickets/${a.ticketId}'),
              ),
          ]),
        );
      },
    );
  }
}

IconData activityIcon(String action) => switch (action) {
      ActivityModel.actionCreated => Icons.add_circle_outline,
      ActivityModel.actionAssigned => Icons.person_add_alt,
      ActivityModel.actionResolved => Icons.check_circle_outline,
      ActivityModel.actionReopened => Icons.replay,
      ActivityModel.actionClosed => Icons.lock_outline,
      ActivityModel.actionPriorityChanged => Icons.flag_outlined,
      ActivityModel.actionCategoryChanged => Icons.category_outlined,
      _ => Icons.sync_alt,
    };

Color activityColor(String action) => switch (action) {
      ActivityModel.actionCreated => Colors.blue,
      ActivityModel.actionAssigned => Colors.purple,
      ActivityModel.actionResolved => Colors.green,
      ActivityModel.actionReopened => Colors.red,
      ActivityModel.actionClosed => Colors.grey,
      _ => Colors.orange,
    };

String describeActivity(ActivityModel a) {
  final who = a.actorName ?? 'System';
  return switch (a.action) {
    ActivityModel.actionCreated => 'created by $who',
    ActivityModel.actionAssigned =>
      a.newValue == null ? 'unassigned by $who' : 'assigned by $who',
    ActivityModel.actionResolved => 'resolved by $who',
    ActivityModel.actionReopened => 'reopened by $who',
    ActivityModel.actionClosed => 'closed by $who',
    ActivityModel.actionPriorityChanged =>
      'priority ${Fmt.priority(a.oldValue)} → ${Fmt.priority(a.newValue)} by $who',
    ActivityModel.actionCategoryChanged =>
      'category ${a.oldValue} → ${a.newValue} by $who',
    _ => 'status ${Fmt.status(a.oldValue)} → ${Fmt.status(a.newValue)} by $who',
  };
}
