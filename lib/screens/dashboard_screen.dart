import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
import '../models/activity_model.dart';
import '../models/ticket_model.dart';
import '../models/ticket_stats.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/tickets_provider.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import 'employee/employee_home_screen.dart';

/// Role-aware dashboard: employees see their own tickets; IT Support and
/// administrators get a command-center view of the whole queue.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) return const LoadingView();
    if (!user.isStaff) return EmployeeHomeScreen(user: user);

    Future<void> refresh() async {
      ref.invalidate(ticketStatsProvider);
      ref.invalidate(recentActivityProvider);
      ref.invalidate(ticketListProvider(TicketScope.assignedToMe));
    }

    return ColoredBox(
      color: const Color(0xFFF4F6FB),
      child: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeroBanner(user: user),
                    const SizedBox(height: 24),
                    const _SectionTitle(
                      'Support queue',
                      icon: Icons.dashboard_customize_rounded,
                    ),
                    _StatsSection(
                      scope: 'all',
                      onTap: () => context.go('/queue'),
                    ),
                    const SizedBox(height: 24),
                    LayoutBuilder(
                      builder: (context, c) {
                        const assigned = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SectionTitle(
                              'Assigned to me',
                              icon: Icons.assignment_ind_rounded,
                            ),
                            _AssignedToMe(),
                          ],
                        );
                        const activity = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SectionTitle(
                              'Recent activity',
                              icon: Icons.bolt_rounded,
                            ),
                            _RecentActivity(),
                          ],
                        );
                        if (c.maxWidth < 860) {
                          return const Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              assigned,
                              SizedBox(height: 24),
                              activity,
                            ],
                          );
                        }
                        return const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: assigned),
                            SizedBox(width: 20),
                            Expanded(child: activity),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    const _SectionTitle(
                      'My tickets',
                      icon: Icons.confirmation_number_rounded,
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final stats = ref.watch(ticketStatsProvider('mine'));
                        return stats.when(
                          loading: () =>
                              const SizedBox(height: 130, child: LoadingView()),
                          error: (e, _) => ErrorView(
                            error: e,
                            onRetry: () =>
                                ref.invalidate(ticketStatsProvider('mine')),
                          ),
                          data: (TicketStats s) => _StatGrid(
                            children: [
                              _StatCard(
                                label: 'Tiket Saya',
                                value: s.total,
                                icon: Icons.confirmation_number,
                                color: AppTheme.primary,
                                onTap: () => context.go('/tickets'),
                              ),
                              _StatCard(
                                label: 'Diproses',
                                value: s.inProgress,
                                icon: Icons.build_circle_outlined,
                                color: AppTheme.getStatusColor('in_progress'),
                                onTap: () => context.go('/tickets'),
                              ),
                              _StatCard(
                                label: 'Open',
                                value: s.open,
                                icon: Icons.mark_email_unread_outlined,
                                color: AppTheme.getStatusColor('open'),
                                onTap: () => context.go('/tickets'),
                              ),
                              _StatCard(
                                label: 'Selesai',
                                value: s.resolved,
                                icon: Icons.check_circle_outline,
                                color: AppTheme.getStatusColor('resolved'),
                                onTap: () => context.go('/tickets'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    const _SectionTitle(
                      'Tiket Terbaru',
                      icon: Icons.history_rounded,
                    ),
                    const _RecentTickets(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gradient welcome banner: time-aware greeting, role badge, today's date,
/// the "needs attention" headline number and quick actions.
class _HeroBanner extends ConsumerWidget {
  const _HeroBanner({required this.user});
  final UserModel user;

  static String _greeting(int hour) => switch (hour) {
    < 11 => 'Selamat pagi',
    < 15 => 'Selamat siang',
    < 18 => 'Selamat sore',
    _ => 'Selamat malam',
  };

  static const _days = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];
  static const _months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final stats = ref.watch(ticketStatsProvider('all')).valueOrNull;
    final attention = stats == null ? null : stats.open + stats.inProgress;
    final first = user.fullName.split(' ').first;

    Widget action(String label, IconData icon, String path, {Key? key}) =>
        Material(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.go(path),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    final headline = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                user.isSuperAdmin
                    ? Icons.workspace_premium_rounded
                    : user.isAdmin
                    ? Icons.admin_panel_settings_rounded
                    : Icons.support_agent_rounded,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                Fmt.role(user.role).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${_greeting(now.hour)}, $first 👋',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]} ${now.year}'
          ' · ${AppConstants.appShortName}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            action('Buat Tiket', Icons.add_rounded, '/tickets/new'),
            action('Antrian', Icons.support_agent_rounded, '/queue'),
            action('Ringkasan', Icons.insights_rounded, '/summary'),
            if (user.isAdmin) ...[
              action('Pengguna', Icons.group_rounded, '/admin/users'),
              action('Backup & Data', Icons.backup_rounded, '/admin/data'),
            ],
          ],
        ),
      ],
    );

    final counter = Container(
      width: 190,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: Color(0xFFFDE68A),
          ),
          const SizedBox(height: 8),
          Text(
            attention == null ? '–' : '$attention',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'tiket perlu ditangani',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
          ),
          if (stats != null && stats.unassigned > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${stats.unassigned} belum ditugaskan',
              style: const TextStyle(
                color: Color(0xFFFDE68A),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF312E81), Color(0xFF2563EB), Color(0xFF0EA5E9)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative glow circles
          Positioned(
            right: -60,
            top: -80,
            child: _Glow(size: 240, opacity: 0.12),
          ),
          Positioned(
            left: -40,
            bottom: -90,
            child: _Glow(size: 200, opacity: 0.08),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, c) => c.maxWidth < 620
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [headline, const SizedBox(height: 18), counter],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: headline),
                        const SizedBox(width: 20),
                        counter,
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.opacity});
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF0EA5E9)],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800, color: AppTheme.ink),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Queue KPIs: gradient-accent cards + the status distribution bar.
class _StatsSection extends ConsumerWidget {
  const _StatsSection({required this.scope, this.onTap});
  final String scope;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(ticketStatsProvider(scope));
    return stats.when(
      loading: () => const SizedBox(height: 120, child: LoadingView()),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(ticketStatsProvider(scope)),
      ),
      data: (TicketStats s) {
        final total = s.total == 0 ? 1 : s.total;
        final cards = [
          _KpiCard(
            label: 'Unassigned',
            caption: 'Belum ditugaskan',
            value: s.unassigned,
            share: s.unassigned / total,
            icon: Icons.inbox_rounded,
            colors: const [Color(0xFFF43F5E), Color(0xFFF97316)],
            onTap: onTap,
          ),
          _KpiCard(
            label: 'Total tickets',
            caption: 'Semua tiket',
            value: s.total,
            share: 1,
            icon: Icons.confirmation_number_rounded,
            colors: const [Color(0xFF4F46E5), Color(0xFF2563EB)],
            onTap: onTap,
          ),
          _KpiCard(
            label: 'Open',
            caption: 'Menunggu',
            value: s.open,
            share: s.open / total,
            icon: Icons.mark_email_unread_rounded,
            colors: const [Color(0xFF2563EB), Color(0xFF06B6D4)],
            onTap: onTap,
          ),
          _KpiCard(
            label: 'In progress',
            caption: 'Sedang diproses',
            value: s.inProgress,
            share: s.inProgress / total,
            icon: Icons.build_circle_rounded,
            colors: const [Color(0xFFF59E0B), Color(0xFFEAB308)],
            onTap: onTap,
          ),
          _KpiCard(
            label: 'Resolved',
            caption: 'Selesai',
            value: s.resolved,
            share: s.resolved / total,
            icon: Icons.verified_rounded,
            colors: const [Color(0xFF10B981), Color(0xFF14B8A6)],
            onTap: onTap,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth >= 1000
                    ? 5
                    : c.maxWidth >= 640
                    ? 3
                    : 2;
                const gap = 14.0;
                final w = (c.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final k in cards) SizedBox(width: w, child: k),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            _StatusBar(stats: s),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.caption,
    required this.value,
    required this.share,
    required this.icon,
    required this.colors,
    this.onTap,
  });
  final String label;
  final String caption;
  final int value;
  final double share;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE8ECF4)),
      boxShadow: [
        BoxShadow(
          color: colors.first.withValues(alpha: 0.10),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: colors,
                      ),
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: colors.first.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const Spacer(),
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                      height: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  children: [
                    Container(height: 6, color: const Color(0xFFEFF2F8)),
                    FractionallySizedBox(
                      widthFactor: share.clamp(0, 1).toDouble(),
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: colors),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Part-to-whole of the ticket states: one stacked bar (2px gaps, rounded
/// ends) with a legend that carries name + count, so state is never
/// identified by color alone. Each segment has a tooltip.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.stats});
  final TicketStats stats;

  @override
  Widget build(BuildContext context) {
    final parts = [
      ('Open', stats.open, AppTheme.getStatusColor('open')),
      ('In progress', stats.inProgress, AppTheme.getStatusColor('in_progress')),
      ('Resolved', stats.resolved, AppTheme.getStatusColor('resolved')),
      ('Closed', stats.closed, AppTheme.getStatusColor('closed')),
    ];
    final sum = parts.fold<int>(0, (a, p) => a + p.$2);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8ECF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Distribusi status tiket',
            style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.ink),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 14,
              child: sum == 0
                  ? Container(color: const Color(0xFFEFF2F8))
                  : Row(
                      children: [
                        for (final (i, p) in parts.indexed)
                          if (p.$2 > 0)
                            Expanded(
                              flex: p.$2,
                              child: Tooltip(
                                message:
                                    '${p.$1}: ${p.$2} (${(p.$2 * 100 / sum).round()}%)',
                                child: Container(
                                  margin: EdgeInsets.only(
                                    right: i == parts.length - 1 ? 0 : 2,
                                  ),
                                  color: p.$3,
                                ),
                              ),
                            ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              for (final p in parts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: p.$3,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${p.$1} ',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.muted,
                      ),
                    ),
                    Text(
                      '${p.$2}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ),
            ],
          ),
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
        onRetry: () =>
            ref.invalidate(ticketListProvider(TicketScope.assignedToMe)),
      ),
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
        return Column(
          children: [
            for (final t in active)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TicketTileCompact(ticket: t),
              ),
          ],
        );
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
        onRetry: () =>
            ref.read(ticketListProvider(TicketScope.mine).notifier).refresh(),
      ),
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
                    Icon(
                      Icons.inbox_outlined,
                      size: 40,
                      color: AppTheme.muted.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No tickets yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Having an IT problem? Create a ticket.',
                      style: TextStyle(color: AppTheme.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Column(
          children: [
            for (final t in recent)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TicketTileCompact(ticket: t),
              ),
          ],
        );
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
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(recentActivityProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const _SoftCard(
            child: EmptyView(
              icon: Icons.history,
              title: 'No activity yet',
              message: 'Updates on your tickets will appear here.',
            ),
          );
        }
        return _SoftCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              for (final (i, a) in items.indexed)
                InkWell(
                  onTap: () => context.push('/tickets/${a.ticketId}'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // timeline rail
                          SizedBox(
                            width: 34,
                            child: Column(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: activityColor(a.action)
                                        .withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    activityIcon(a.action),
                                    size: 16,
                                    color: activityColor(a.action),
                                  ),
                                ),
                                if (i < items.length - 1)
                                  Expanded(
                                    child: Container(
                                      width: 2,
                                      margin: const EdgeInsets.only(top: 4),
                                      color: const Color(0xFFE8ECF4),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${a.ticketNumber ?? ''} ${describeActivity(a)}'
                                        .trim(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.ink,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      if (a.ticketSubject != null)
                                        a.ticketSubject!,
                                      Fmt.relative(a.createdAt),
                                    ].join(' • '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.muted,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// White rounded card with a soft border, used across the staff dashboard.
class _SoftCard extends StatelessWidget {
  const _SoftCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE8ECF4)),
    ),
    child: child,
  );
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
                child: const Icon(
                  Icons.confirmation_number,
                  size: 20,
                  color: AppTheme.muted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.ticketNumber,
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ticket.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.muted,
                      ),
                    ),
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
                  Text(
                    '$value',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
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
        children: [
          for (final child in children) SizedBox(width: w, child: child),
        ],
      );
    },
  );
}
