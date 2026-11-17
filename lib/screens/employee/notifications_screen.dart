import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/app_notification.dart';
import '../../providers/tickets_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';
import '../../widgets/employee_ui.dart';

/// "10. Notifikasi": ticket events and IT Support comments, newest first.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  int _tab = 0; // 0 Semua, 1 Tiket, 2 Sistem

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsProvider);
    final all = async.valueOrNull ?? const <AppNotification>[];
    final ticket = all.where((n) => !n.isSystem).toList();
    final system = all.where((n) => n.isSystem).toList();
    final shown = switch (_tab) {
      1 => ticket,
      2 => system,
      _ => all,
    };

    return Scaffold(
      backgroundColor: EColors.page,
      appBar: EHeader(
        title: 'Notifikasi',
        onBack: () => context.go('/dashboard'),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                for (final (i, label, count) in [
                  (0, 'Semua', null),
                  (1, 'Tiket', ticket.length),
                  (2, 'Sistem', null),
                ]) ...[
                  Expanded(
                    child: _Pill(
                      label: label,
                      count: count,
                      selected: _tab == i,
                      onTap: () => setState(() => _tab = i),
                    ),
                  ),
                  if (i < 2) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: async.when(
              skipLoadingOnRefresh: true,
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(notificationsProvider),
              ),
              data: (_) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(notificationsProvider);
                  await ref
                      .read(notificationsProvider.future)
                      .catchError((_) => const <AppNotification>[]);
                },
                child: shown.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 60),
                          EmptyView(
                            icon: Icons.notifications_none_rounded,
                            title: 'Belum ada notifikasi',
                            message: 'Pembaruan tiket dan komentar IT Support akan muncul di sini.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _NotificationTile(shown[i]),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? EColors.blue : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: selected ? Colors.white : EColors.text,
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.25)
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : EColors.muted,
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
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile(this.n);
  final AppNotification n;

  (IconData, Color) get _style => switch (n.kind) {
    'comment' => (Icons.forum_rounded, EColors.teal),
    'resolved' || 'closed' => (Icons.check_circle_rounded, EColors.green),
    'created' => (Icons.confirmation_number_rounded, EColors.red),
    'reopened' => (Icons.replay_rounded, EColors.red),
    'system' => (Icons.settings_suggest_rounded, EColors.purple),
    _ => (Icons.notifications_active_rounded, EColors.amber),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _style;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: n.ticketId == null
            ? null
            : () => context.push('/tickets/${n.ticketId}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: EColors.ink,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Text(
                          Fmt.relative(n.time),
                          style: const TextStyle(
                            fontSize: 11,
                            color: EColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n.body,
                      style: const TextStyle(
                        color: EColors.text,
                        fontSize: 13,
                        height: 1.35,
                      ),
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
}
