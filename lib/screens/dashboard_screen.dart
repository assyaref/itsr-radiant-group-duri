import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
import '../models/activity_model.dart';
import '../models/ticket_model.dart';
import '../models/ticket_stats.dart';
import '../providers/auth_provider.dart';
import '../providers/tickets_provider.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';

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
          // Greeting header (matches reference mobile dashboard)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hai, ${user.fullName.split(' ').first}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Selamat datang di ${AppConstants.appShortName}',
                            style: TextStyle(color: AppTheme.muted, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.support_agent, color: AppTheme.primary, size: 24),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Quick action card
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.add_circle_outline, color: AppTheme.primary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Laporkan Masalah IT dengan Cepat!',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kami siap membantu Anda',
                          style: TextStyle(color: AppTheme.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Round "+" button as in the design; fits a 320px phone.
                  IconButton.filled(
                    key: const Key('dashboard_create_ticket'),
                    tooltip: 'Buat Tiket',
                    onPressed: () => context.go('/tickets/new'),
                    iconSize: 28,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Stat cards grid (matches reference: Tiket Saya, Diproses, Menunggu, Selesai)
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
          Consumer(
            builder: (context, ref, _) {
              final stats = ref.watch(ticketStatsProvider('mine'));
              return stats.when(
                loading: () => const SizedBox(height: 130, child: LoadingView()),
                error: (e, _) => ErrorView(
                    error: e, onRetry: () => ref.invalidate(ticketStatsProvider('mine'))),
                data: (TicketStats s) => _StatGrid(children: [
                  _StatCard(
                      label: 'Tiket Saya',
                      value: s.total,
                      icon: Icons.confirmation_number,
                      color: AppTheme.primary,
                      onTap: () => context.go('/tickets')),
                  _StatCard(
                      label: 'Diproses',
                      value: s.inProgress,
                      icon: Icons.build_circle_outlined,
                      color: AppTheme.getStatusColor('in_progress'),
                      onTap: () => context.go('/tickets')),
                  _StatCard(
                      label: 'Menunggu',
                      value: s.open,
                      icon: Icons.mark_email_unread_outlined,
                      color: AppTheme.getStatusColor('open'),
                      onTap: () => context.go('/tickets')),
                  _StatCard(
                      label: 'Selesai',
                      value: s.resolved,
                      icon: Icons.check_circle_outline,
                      color: AppTheme.getStatusColor('resolved'),
                      onTap: () => context.go('/tickets')),
                ]),
              );
            },
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Tiket Terbaru'),
          const _RecentTickets(),
          const SizedBox(height: 20),
          const _SectionTitle('Recent activity'),
          const _RecentActivity(),
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
        padding: const EdgeInsets.only(bottom: 12),
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
      loading: () => const SizedBox(height: 120, child: LoadingView()),
      error: (e, _) => ErrorView(
          error: e, onRetry: () => ref.invalidate(ticketStatsProvider(scope))),
      data: (TicketStats s) => Column(
        children: [
          if (staff)
            _StatCard(
                label: 'Unassigned',
                value: s.unassigned,
                icon: Icons.inbox,
                color: Colors.red[600]!,
                onTap: onTap),
          const SizedBox(height: 12),
          _StatCard(
              label: 'Total tickets',
              value: s.total,
              icon: Icons.confirmation_number,
              color: AppTheme.primary,
              onTap: onTap),
          const SizedBox(height: 12),
          _StatCard(
              label: 'Open',
              value: s.open,
              icon: Icons.mark_email_unread_outlined,
              color: AppTheme.getStatusColor('open'),
              onTap: onTap),
          const SizedBox(height: 12),
          _StatCard(
              label: 'In progress',
              value: s.inProgress,
              icon: Icons.build_circle_outlined,
              color: AppTheme.getStatusColor('in_progress'),
              onTap: onTap),
          const SizedBox(height: 12),
          _StatCard(
              label: 'Resolved',
              value: s.resolved,
              icon: Icons.check_circle_outline,
              color: AppTheme.getStatusColor('resolved'),
              onTap: onTap),
        ],
      ),
    );
  }
}

class _AssignedToMe extends ConsumerWidget {
  const _AssignedToMe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(ticketListProvider(TicketScope.assignedToMe));
    return list.when(
      loading: () => const SizedBox(height: 120, child: LoadingView()),
      error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(ticketListProvider(TicketScope.assignedToMe))),
      data: (s) {
        final active = s.items.where((t) => !t.isFinished).take(5).toList();
        if (active.isEmpty) {
          return Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.task_alt, color: AppTheme.muted),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Nothing assigned to you right now')),
                ],
              ),
            ),
          );
        }
        return Column(children: [
          for (final t in active)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TicketTileCompact(ticket: t),
            ),
        ]);
      },
    );
  }
}

class _RecentTickets extends ConsumerWidget {
  const _RecentTickets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(ticketListProvider(TicketScope.mine));
    return list.when(
      loading: () => const SizedBox(height: 140, child: LoadingView()),
      error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.read(ticketListProvider(TicketScope.mine).notifier).refresh()),
      data: (s) {
        final recent = s.items.take(5).toList();
        if (recent.isEmpty) {
          return Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 40, color: AppTheme.muted.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    Text('No tickets yet',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text('Having an IT problem? Create a ticket.',
                        style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                  ],
                ),
              ),
            ),
          );
        }
        return Column(children: [
          for (final t in recent)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TicketTileCompact(ticket: t),
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
      loading: () => const SizedBox(height: 100, child: LoadingView()),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.invalidate(recentActivityProvider)),
      data: (items) {
        if (items.isEmpty) {
          return Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: EmptyView(
                icon: Icons.history,
                title: 'No activity yet',
                message: 'Updates on your tickets will appear here.',
              ),
            ),
          );
        }
        return Card(
          elevation: 0,
          child: Column(children: [
            for (final a in items)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      ActivityModel.actionCreated => AppTheme.primary,
      ActivityModel.actionAssigned => const Color(0xFF7C3AED),
      ActivityModel.actionResolved => const Color(0xFF10B981),
      ActivityModel.actionReopened => const Color(0xFFEF4444),
      ActivityModel.actionClosed => const Color(0xFF6B7280),
      _ => const Color(0xFFF59E0B),
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

/// Compact ticket tile used in dashboard lists.
class TicketTileCompact extends StatelessWidget {
  const TicketTileCompact({super.key, required this.ticket});
  final TicketModel ticket;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/tickets/${ticket.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.confirmation_number, size: 20, color: AppTheme.muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ticket.ticketNumber,
                        style: const TextStyle(
                            color: AppTheme.ink, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(ticket.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppTheme.muted)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusChip(ticket.status),
                  const SizedBox(height: 6),
                  PriorityChip(ticket.priority),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stat card (single column).
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$value',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Horizontal stat grid: 2 cards on phones, 4 on wide screens.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 700 ? 4 : 2;
          const gap = 12.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final child in children) SizedBox(width: w, child: child)],
          );
        },
      );
}

