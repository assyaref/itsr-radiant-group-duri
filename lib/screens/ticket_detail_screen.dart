import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../models/activity_model.dart';
import '../models/attachment_model.dart';
import '../models/comment_model.dart';
import '../models/ticket_model.dart';
import '../models/ticket_stats.dart';
import '../models/user_model.dart';
import '../providers/attachment_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/tickets_provider.dart';
import '../utils/browser_files.dart' show downloadBytes, listenForPastedFiles;
import '../utils/error_messages.dart';
import '../utils/formatters.dart';
import '../utils/file_picker.dart';
import '../widgets/common.dart';
import '../widgets/employee_ui.dart';

const int kMaxAttachmentDisplaySize = 10 * 1024 * 1024; // 10 MiB

/// "7–9. Detail Tiket" of the employee design: a tinted summary card with the
/// status timeline, pill tabs (Detail · Komentar · Lampiran) and a pinned
/// comment composer. All IT Support / reporter actions are preserved.
class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});
  final String ticketId;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  int _tab = 0; // 0 Detail, 1 Komentar, 2 Lampiran

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(ticketDetailProvider(widget.ticketId));
    final user = ref.watch(currentUserProvider).valueOrNull;

    return detail.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => Scaffold(
        backgroundColor: EColors.page,
        appBar: const EHeader(title: 'Detail Tiket'),
        body: const LoadingView(),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: EColors.page,
        appBar: const EHeader(title: 'Detail Tiket'),
        body: ErrorView(
          error: e,
          onRetry: () => ref.invalidate(ticketDetailProvider(widget.ticketId)),
        ),
      ),
      data: (d) {
        if (user == null) {
          return const Scaffold(
            backgroundColor: EColors.page,
            appBar: EHeader(title: 'Detail Tiket'),
            body: LoadingView(),
          );
        }
        final attachments = ref
            .watch(attachmentsProvider(d.ticket.id))
            .valueOrNull;
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            backgroundColor: EColors.page,
            appBar: const EHeader(title: 'Detail Tiket'),
            body: Column(
              children: [
                _DetailTabs(
                  tab: _tab,
                  commentCount: d.comments.length,
                  attachmentCount: attachments?.length,
                  onChanged: (i) => setState(() => _tab = i),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      _DetailTab(
                        key: const ValueKey('tab_detail'),
                        ticket: d.ticket,
                        user: user,
                        activities: d.activities,
                      ),
                      _CommentsTab(
                        key: const ValueKey('tab_comments'),
                        detail: d,
                        user: user,
                      ),
                      _AttachmentsTab(
                        key: const ValueKey('tab_attachments'),
                        ticket: d.ticket,
                        user: user,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Pill tab switcher (Detail · Komentar n · Lampiran n)
// ---------------------------------------------------------------------------
class _DetailTabs extends StatelessWidget {
  const _DetailTabs({
    required this.tab,
    required this.commentCount,
    required this.attachmentCount,
    required this.onChanged,
  });

  final int tab;
  final int commentCount;
  final int? attachmentCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          for (final (i, label, count) in [
            (0, 'Detail', null),
            (1, 'Komentar', commentCount),
            (2, 'Lampiran', attachmentCount),
          ]) ...[
            Expanded(
              child: _DetailTabPill(
                label: label,
                count: count,
                selected: tab == i,
                onTap: () => onChanged(i),
              ),
            ),
            if (i < 2) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _DetailTabPill extends StatelessWidget {
  const _DetailTabPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? EColors.blueSoft : const Color(0xFFF1F5F9),
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
                    color: selected ? EColors.blue : EColors.text,
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected ? EColors.blue : EColors.muted,
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

// ---------------------------------------------------------------------------
/// Detail tab: tinted summary card + status timeline, then the info card.
class _DetailTab extends StatelessWidget {
  const _DetailTab({
    super.key,
    required this.ticket,
    required this.user,
    required this.activities,
  });
  final TicketModel ticket;
  final UserModel user;
  final List<ActivityModel> activities;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryCard(ticket: t, activities: activities),
          const SizedBox(height: 12),
          _InfoCard(ticket: t),
          if (user.isStaff) ...[
            const SizedBox(height: 12),
            _StaffActions(ticket: t, user: user),
          ] else if (t.reporterId == user.id) ...[
            const SizedBox(height: 12),
            _ReporterActions(ticket: t),
          ],
          if (user.isSuperAdmin) ...[
            const SizedBox(height: 12),
            _DeleteTicketCard(ticket: t),
          ],
        ],
      ),
    );
  }
}

/// Priority-tinted summary card (mockup screen 7): ticket number + priority
/// tag, subject, description, then the Dibuat → Diproses → Selesai timeline.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.ticket, required this.activities});
  final TicketModel ticket;
  final List<ActivityModel> activities;

  (Color bg, Color accent) get _tint => switch (ticket.priority) {
    'critical' || 'high' => (const Color(0xFFFEF2F2), EColors.red),
    'medium' => (const Color(0xFFFFFBEB), const Color(0xFFD97706)),
    'low' => (const Color(0xFFF0FDF4), const Color(0xFF16A34A)),
    _ => (EColors.blueSoft, EColors.blue),
  };

  bool get _processedReached {
    if (const [
      'assigned',
      'in_progress',
      'pending_user',
    ].contains(ticket.status)) {
      return true;
    }
    if (ticket.isFinished) return true;
    return activities.any(
      (a) =>
          a.action == ActivityModel.actionAssigned ||
          (a.action == ActivityModel.actionStatusChanged &&
              const [
                'assigned',
                'in_progress',
                'pending_user',
              ].contains(a.newValue)),
    );
  }

  DateTime? get _processedAt {
    for (final a in activities) {
      final reached =
          a.action == ActivityModel.actionAssigned ||
          (a.action == ActivityModel.actionStatusChanged &&
              const [
                'assigned',
                'in_progress',
                'pending_user',
              ].contains(a.newValue));
      if (reached) return a.createdAt;
    }
    return _processedReached ? ticket.updatedAt : null;
  }

  DateTime? get _finishedAt {
    if (!ticket.isFinished) return null;
    return ticket.resolvedAt ?? ticket.closedAt ?? ticket.updatedAt;
  }

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final (bg, accent) = _tint;
    final processed = _processedReached;
    final processedAt = _processedAt;
    final finishedAt = _finishedAt;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    t.ticketNumber,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  ETag.priority(t.priority),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                t.subject,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: EColors.ink,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.description,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: EColors.text,
                ),
              ),
              const SizedBox(height: 14),
              Divider(color: accent.withValues(alpha: 0.18), height: 1),
              const SizedBox(height: 14),
              Row(
                children: [
                  _TimelineStep(
                    icon: Icons.desktop_windows_outlined,
                    label: 'Dibuat',
                    time: t.createdAt,
                    done: true,
                    accent: EColors.blue,
                  ),
                  _TimelineConnector(done: processed, accent: EColors.blue),
                  _TimelineStep(
                    icon: Icons.build_outlined,
                    label: 'Diproses',
                    time: processed ? processedAt : null,
                    done: processed,
                    accent: EColors.blue,
                  ),
                  _TimelineConnector(
                    done: finishedAt != null,
                    accent: EColors.green,
                  ),
                  _TimelineStep(
                    icon: Icons.check_rounded,
                    label: 'Selesai',
                    time: finishedAt,
                    done: finishedAt != null,
                    accent: EColors.green,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.icon,
    required this.label,
    required this.time,
    required this.done,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final DateTime? time;
  final bool done;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? accent : const Color(0xFFE2E8F0),
              border: Border.all(
                color: done ? accent : const Color(0xFFCBD5E1),
              ),
            ),
            child: Icon(
              icon,
              size: 17,
              color: done ? Colors.white : EColors.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: done ? EColors.ink : EColors.muted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            time == null ? '—' : Fmt.dateTime(time!),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: EColors.muted),
          ),
        ],
      ),
    );
  }
}

class _TimelineConnector extends StatelessWidget {
  const _TimelineConnector({required this.done, required this.accent});
  final bool done;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Align with the circle centers (icon is 34 tall, label sits below).
      padding: const EdgeInsets.only(bottom: 30),
      child: Container(
        height: 2,
        color: done ? accent : const Color(0xFFE2E8F0),
      ),
    );
  }
}

/// "Informasi" card: kategori + prioritas tiles, then the meta rows.
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.ticket});
  final TicketModel ticket;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final meta = <(String, String)>[
      ('Pelapor', t.reporterName ?? '—'),
      ('Ditugaskan', t.assigneeName ?? 'Belum ditugaskan'),
      ('Dibuat', Fmt.dateTime(t.createdAt)),
      ('Pembaruan', Fmt.dateTime(t.updatedAt)),
      if (t.resolvedAt != null)
        ('Diproses selesai', Fmt.dateTime(t.resolvedAt!)),
      if (t.closedAt != null) ('Ditutup', Fmt.dateTime(t.closedAt!)),
    ];
    return ECard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Informasi',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: EColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  icon: Icons.category_outlined,
                  label: 'Kategori',
                  value: t.category,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InfoTile(
                  icon: Icons.flag_outlined,
                  label: 'Prioritas',
                  value: Fmt.priority(t.priority),
                  valueColor: EColors.priority(t.priority),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final (label, value) in meta)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 108,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: EColors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: EColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (t.resolution != null && t.resolution!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resolusi',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF15803D),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(t.resolution!, style: const TextStyle(height: 1.4)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: EColors.line),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: EColors.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: EColors.muted),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? EColors.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
/// Runs an action with a busy flag and user-friendly error reporting.
mixin _ActionRunner<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;

  Future<void> run(Future<void> Function() action, String success) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) showSnack(context, success);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

/// Superadmin-only "danger zone": permanently delete the ticket.
/// The `delete_ticket` RPC re-checks the superadmin role server-side.
class _DeleteTicketCard extends ConsumerStatefulWidget {
  const _DeleteTicketCard({required this.ticket});
  final TicketModel ticket;

  @override
  ConsumerState<_DeleteTicketCard> createState() => _DeleteTicketCardState();
}

class _DeleteTicketCardState extends ConsumerState<_DeleteTicketCard> {
  bool _busy = false;

  Future<void> _delete() async {
    final t = widget.ticket;
    final ok = await showConfirmDialog(
      context,
      title: 'Hapus tiket ${t.ticketNumber}?',
      message:
          'Tiket beserta komentar, riwayat aktivitas, dan data lampirannya '
          'akan dihapus permanen. Tindakan ini tidak dapat dibatalkan.',
      confirmLabel: 'Hapus permanen',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(ticketActionsProvider).deleteTicket(t.id);
      if (!mounted) return;
      showSnack(context, 'Tiket ${t.ticketNumber} dihapus');
      GoRouter.maybeOf(context)?.go('/queue');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFFECACA)),
    ),
    child: Row(
      children: [
        const Icon(Icons.shield_outlined, color: Color(0xFFDC2626)),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Super Admin · hapus tiket ini secara permanen',
            style: TextStyle(
              color: Color(0xFF991B1B),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const Key('delete_ticket_button'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
          ),
          onPressed: _busy ? null : _delete,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.delete_forever, size: 18),
          label: const Text('Hapus'),
        ),
      ],
    ),
  );
}

class _StaffActions extends ConsumerStatefulWidget {
  const _StaffActions({required this.ticket, required this.user});
  final TicketModel ticket;
  final UserModel user;

  @override
  ConsumerState<_StaffActions> createState() => _StaffActionsState();
}

class _StaffActionsState extends ConsumerState<_StaffActions>
    with _ActionRunner {
  TicketActions get _actions => ref.read(ticketActionsProvider);
  TicketModel get t => widget.ticket;

  static const _statusLabels = {
    AppConstants.statusInProgress: ('Mulai Kerjakan', Icons.play_arrow),
    AppConstants.statusPendingUser: (
      'Menunggu Pengguna',
      Icons.hourglass_bottom,
    ),
    AppConstants.statusResolved: ('Selesaikan', Icons.check_circle),
    AppConstants.statusClosed: ('Tutup', Icons.lock),
    AppConstants.statusReopened: ('Buka Ulang', Icons.replay),
    AppConstants.statusOpen: ('Kembalikan ke Antrian', Icons.undo),
  };

  Future<void> _changeStatus(String status) async {
    String? resolution;
    if (status == AppConstants.statusResolved ||
        (status == AppConstants.statusClosed &&
            (t.resolution ?? '').trim().isEmpty)) {
      resolution = await showTextInputDialog(
        context,
        title: status == AppConstants.statusResolved
            ? 'Selesaikan Tiket'
            : 'Tutup Tiket',
        label: status == AppConstants.statusResolved
            ? 'Apa yang dilakukan untuk menyelesaikannya? (terlihat oleh pelapor)'
            : 'Alasan menutup (mis. duplikat ITSR-00012)',
        confirmLabel: status == AppConstants.statusResolved
            ? 'Selesaikan'
            : 'Tutup',
        initialValue: t.resolution,
        minLength: 5,
      );
      if (resolution == null) return;
    } else {
      final ok = await showConfirmDialog(
        context,
        title: 'Ubah status',
        message:
            'Ubah ${t.ticketNumber} dari "${Fmt.statusId(t.status)}" menjadi "${Fmt.statusId(status)}"? '
            'Pelapor akan diberitahu lewat email.',
        confirmLabel: _statusLabels[status]?.$1 ?? 'Konfirmasi',
      );
      if (!ok) return;
    }
    await run(
      () => _actions.changeStatus(t.id, status, resolution: resolution),
      'Status diubah ke ${Fmt.statusId(status)}',
    );
  }

  Future<void> _assign() async {
    final staff = await ref.read(assignableStaffProvider.future).catchError((
      Object e,
    ) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
      return <StaffMember>[];
    });
    if (!mounted || staff.isEmpty) return;
    final chosen = await showDialog<StaffMember>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Tugaskan tiket ke'),
        children: [
          for (final s in staff)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  s.id == t.assignedToId
                      ? Icons.radio_button_checked
                      : Icons.person_outline,
                ),
                title: Text(s.fullName),
                subtitle: Text('${s.employeeNumber} • ${Fmt.role(s.role)}'),
              ),
            ),
        ],
      ),
    );
    if (chosen == null || chosen.id == t.assignedToId) return;
    await run(
      () => _actions.assignTicket(t.id, chosen.id),
      'Ditugaskan ke ${chosen.fullName}',
    );
  }

  Future<void> _priority(String? p) async {
    if (p == null || p == t.priority) return;
    await run(
      () => _actions.changePriority(t.id, p),
      'Prioritas diubah ke ${Fmt.priority(p)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final next = AppConstants.staffTransitions[t.status] ?? const [];
    final mine = t.assignedToId == widget.user.id;
    return ECard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Aksi IT Support',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: EColors.ink,
                  ),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!mine && !t.isFinished)
                FilledButton.icon(
                  key: const Key('accept_ticket_button'),
                  onPressed: busy
                      ? null
                      : () => run(
                          () => _actions.acceptTicket(t.id),
                          'Anda sekarang ditugaskan ke tiket ini',
                        ),
                  icon: const Icon(Icons.pan_tool_alt),
                  label: Text(
                    t.assignedToId == null ? 'Terima Tiket' : 'Ambil Alih',
                  ),
                ),
              if (!t.isFinished)
                OutlinedButton.icon(
                  onPressed: busy ? null : _assign,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Tugaskan ke…'),
                ),
              for (final s in next)
                OutlinedButton.icon(
                  key: Key('status_$s'),
                  onPressed: busy ? null : () => _changeStatus(s),
                  icon: Icon(_statusLabels[s]?.$2 ?? Icons.sync_alt),
                  label: Text(_statusLabels[s]?.$1 ?? Fmt.statusId(s)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              key: ValueKey('priority_${t.priority}'),
              initialValue: t.priority,
              decoration: const InputDecoration(
                labelText: 'Prioritas',
                isDense: true,
              ),
              items: [
                for (final p in AppConstants.priorities)
                  DropdownMenuItem(value: p, child: Text(Fmt.priority(p))),
              ],
              onChanged: busy ? null : _priority,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReporterActions extends ConsumerStatefulWidget {
  const _ReporterActions({required this.ticket});
  final TicketModel ticket;

  @override
  ConsumerState<_ReporterActions> createState() => _ReporterActionsState();
}

class _ReporterActionsState extends ConsumerState<_ReporterActions>
    with _ActionRunner {
  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final actions = ref.read(ticketActionsProvider);
    final String message;
    final List<Widget> buttons = [];

    switch (t.status) {
      case AppConstants.statusResolved:
        message = 'IT Support menandai tiket ini selesai. Apakah masalah Anda sudah teratasi?';
        buttons.add(
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final ok = await showConfirmDialog(
                      context,
                      title: 'Tutup Tiket',
                      message:
                          'Tutup ${t.ticketNumber}? Anda masih bisa membuka ulang jika masalah muncul lagi.',
                      confirmLabel: 'Tutup Tiket',
                    );
                    if (ok) {
                      await run(
                        () => actions.confirmClose(t.id),
                        'Tiket ditutup. Terima kasih!',
                      );
                    }
                  },
            icon: const Icon(Icons.check),
            label: const Text('Ya, tutup tiket'),
          ),
        );
      case AppConstants.statusClosed:
        message = 'Tiket ini sudah ditutup.';
      case AppConstants.statusPendingUser:
        message = 'IT Support menunggu informasi dari Anda. Silakan balas lewat tab Komentar.';
      default:
        message = 'IT Support akan memperbarui tiket ini; Anda akan diberitahu lewat email.';
    }
    if (t.isFinished) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final reason = await showTextInputDialog(
                    context,
                    title: 'Buka Ulang Tiket',
                    label: 'Mengapa masalah belum teratasi?',
                    confirmLabel: 'Buka Ulang',
                    minLength: 5,
                  );
                  if (reason != null) {
                    await run(
                      () => actions.reopen(t.id, reason),
                      'Tiket dibuka ulang. IT Support telah diberitahu.',
                    );
                  }
                },
          icon: const Icon(Icons.replay),
          label: const Text('Buka Ulang'),
        ),
      );
    }

    return ECard(
      color: EColors.blueSoft,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: EColors.blue),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          if (buttons.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: buttons),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
/// Komentar tab: activity + comment timeline, pinned composer at the bottom.
class _CommentsTab extends ConsumerStatefulWidget {
  const _CommentsTab({super.key, required this.detail, required this.user});
  final TicketDetail detail;
  final UserModel user;

  @override
  ConsumerState<_CommentsTab> createState() => _CommentsTabState();
}

class _CommentsTabState extends ConsumerState<_CommentsTab> with _ActionRunner {
  final _text = TextEditingController();
  bool _internal = false;
  String? _pickedFileName;
  String? _pickedMimeType;
  Uint8List? _pickedBytes;
  void Function()? _stopPasteListener;

  @override
  void initState() {
    super.initState();
    // Ctrl/Cmd+V of a screenshot or copied image attaches it to the comment.
    _stopPasteListener = listenForPastedFiles(
      (file) {
        if (!mounted || busy) return;
        if (file.size > kMaxAttachmentDisplaySize) {
          showSnack(context, 'Gambar lebih dari 10 MB', error: true);
          return;
        }
        setState(() {
          _pickedFileName = file.name;
          _pickedMimeType = file.mimeType;
          _pickedBytes = file.bytes;
        });
        showSnack(context, 'Gambar ditempel. Tekan kirim untuk mengunggah.');
      },
      onUnsupported: (_) {
        if (!mounted) return;
        showSnack(
          context,
          'Hanya gambar PNG/JPG yang bisa ditempel',
          error: true,
        );
      },
    );
  }

  @override
  void dispose() {
    _stopPasteListener?.call();
    _text.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final content = _text.text.trim();
    if (content.isEmpty && _pickedBytes == null) {
      showSnack(
        context,
        'Tulis komentar atau lampirkan file terlebih dahulu',
        error: true,
      );
      return;
    }
    await run(() async {
      // Upload attachment first if a file was picked (same bucket as ticket creation attachments).
      if (_pickedBytes != null) {
        await ref
            .read(attachmentActionsProvider)
            .uploadAttachment(
              ticketId: widget.detail.ticket.id,
              fileName: _pickedFileName!,
              mimeType: _pickedMimeType!,
              bytes: _pickedBytes!,
              uploadedBy: widget.user.id,
            );
        setState(() {
          _pickedFileName = null;
          _pickedMimeType = null;
          _pickedBytes = null;
        });
      }
      if (content.isNotEmpty) {
        await ref
            .read(ticketActionsProvider)
            .addComment(
              widget.detail.ticket.id,
              content,
              isInternal: _internal,
            );
        _text.clear();
      }
      setState(() => _internal = false);
    }, _internal ? 'Catatan internal ditambahkan' : 'Komentar terkirim');
  }

  Future<void> _editComment(CommentModel c) async {
    final text = await showTextInputDialog(
      context,
      title: 'Edit komentar',
      label: 'Komentar',
      confirmLabel: 'Simpan',
      cancelLabel: 'Batal',
      initialValue: c.content,
      minLength: 1,
      maxLength: 5000,
    );
    if (text == null || text == c.content.trim()) return;
    await run(
      () => ref
          .read(ticketActionsProvider)
          .editComment(widget.detail.ticket.id, c.id, text),
      'Komentar diperbarui',
    );
  }

  Future<void> _deleteComment(CommentModel c) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Hapus komentar?',
      message:
          'Isi komentar akan dihapus permanen dan diganti dengan '
          '"Pesan ini telah dihapus".',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok) return;
    await run(
      () => ref
          .read(ticketActionsProvider)
          .deleteComment(widget.detail.ticket.id, c.id),
      'Komentar dihapus',
    );
  }

  Future<void> _deleteAttachment(AttachmentModel f) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Hapus lampiran?',
      message:
          '"${f.fileName}" akan dihapus permanen, termasuk dari '
          'Google Drive.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok) return;
    await run(
      () => ref
          .read(attachmentActionsProvider)
          .deleteAttachment(widget.detail.ticket.id, f.id),
      'Lampiran dihapus',
    );
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.user.isStaff;
    final reporterId = widget.detail.ticket.reporterId;
    final me = widget.user;
    final closedForMe =
        !staff && widget.detail.ticket.status == AppConstants.statusClosed;
    final attachments =
        ref.watch(attachmentsProvider(widget.detail.ticket.id)).valueOrNull ??
        const <AttachmentModel>[];
    final events = <(DateTime, Widget)>[
      for (final a in widget.detail.activities) (a.createdAt, _ActivityItem(a)),
      for (final f in attachments)
        (
          f.createdAt,
          _CommentItem.attachment(
            f,
            fromReporter: f.uploadedBy == reporterId,
            mine: f.uploadedBy == widget.user.id,
            onDelete:
                !busy && !closedForMe && (f.uploadedBy == me.id || me.isAdmin)
                ? () => _deleteAttachment(f)
                : null,
          ),
        ),
      for (final c in widget.detail.comments)
        (
          c.createdAt,
          _CommentItem(
            c,
            fromReporter: c.authorId == reporterId,
            mine: c.authorId == widget.user.id,
            onEdit: !busy && !c.isDeleted && c.authorId == me.id
                ? () => _editComment(c)
                : null,
            onDelete:
                !busy && !c.isDeleted && (c.authorId == me.id || me.isAdmin)
                ? () => _deleteComment(c)
                : null,
          ),
        ),
    ]..sort((x, y) => y.$1.compareTo(x.$1)); // newest first

    // The list is reversed: newest at the bottom and opened scrolled to it.
    // A day chip sits above the first (oldest) entry of each day.
    final rows = <Widget>[];
    for (var i = 0; i < events.length; i++) {
      rows.add(events[i].$2);
      final day = DateUtils.dateOnly(events[i].$1.toLocal());
      final olderDay = i + 1 < events.length
          ? DateUtils.dateOnly(events[i + 1].$1.toLocal())
          : null;
      if (olderDay != day) rows.add(_DayChip(day));
    }

    // Chat layout: history scrolls on top, the composer stays pinned below.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFEFF4FF), EColors.page],
              ),
            ),
            child: events.isEmpty
                ? const _EmptyChat()
                : ListView(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    children: rows,
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: EColors.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('comment_field'),
                          controller: _text,
                          enabled: !busy,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 5000,
                          scrollPadding: const EdgeInsets.only(bottom: 80),
                          decoration: InputDecoration(
                            hintText: staff
                                ? 'Balas pelapor / catatan teknis (Ctrl+V untuk tempel gambar)'
                                : 'Tambah detail atau balas (Ctrl+V untuk tempel gambar)',
                            counterText: '',
                            filled: true,
                            fillColor: EColors.page,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        key: const Key('pick_attachment_button'),
                        onPressed: busy
                            ? null
                            : () async {
                                final picked = await pickFile();
                                if (picked != null) {
                                  setState(() {
                                    _pickedFileName = picked.$1;
                                    _pickedMimeType = picked.$2;
                                    _pickedBytes = picked.$3;
                                  });
                                }
                              },
                        icon: const Icon(Icons.attach_file, size: 20),
                        tooltip:
                            'Lampirkan file (atau tempel gambar dengan Ctrl+V)',
                      ),
                      const SizedBox(width: 4),
                      Material(
                        color: EColors.blue,
                        shape: const CircleBorder(),
                        child: IconButton(
                          key: const Key('post_comment_button'),
                          tooltip: _internal ? 'Tambah catatan' : 'Kirim',
                          onPressed: busy ? null : _post,
                          icon: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 19,
                                ),
                        ),
                      ),
                    ],
                  ),
                  if (_pickedBytes != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
                      child: Row(
                        children: [
                          if (_pickedMimeType?.startsWith('image/') ?? false)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(
                                _pickedBytes!,
                                key: const Key('pasted_image_preview'),
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.image,
                                  size: 16,
                                  color: EColors.blue,
                                ),
                              ),
                            )
                          else
                            const Icon(
                              Icons.insert_drive_file,
                              size: 16,
                              color: EColors.blue,
                            ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _pickedFileName!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: EColors.blue,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => setState(() {
                              _pickedFileName = null;
                              _pickedMimeType = null;
                              _pickedBytes = null;
                            }),
                            child: const Icon(
                              Icons.close,
                              size: 18,
                              color: EColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (staff)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      value: _internal,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => _internal = v ?? false),
                      title: const Text('Catatan internal'),
                      subtitle: const Text(
                        'Hanya terlihat oleh IT Support & Admin; tidak ada email dikirim',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Centered system pill for an activity event (created/assigned/resolved/...).
class _ActivityItem extends StatelessWidget {
  const _ActivityItem(this.a);
  final ActivityModel a;

  @override
  Widget build(BuildContext context) {
    final color = activityColor(a.action);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(activityIcon(a.action), size: 12, color: color),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: describeActivity(a),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: EColors.ink,
                          ),
                        ),
                        if (a.note != null && a.note!.isNotEmpty)
                          TextSpan(
                            text: ' · “${a.note}”',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        TextSpan(
                          text: '  ${Fmt.time(a.createdAt)}',
                          style: const TextStyle(
                            color: EColors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 11.5, color: EColors.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Date separator between chat days.
class _DayChip extends StatelessWidget {
  const _DayChip(this.day);
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final label = day == today
        ? 'Hari ini'
        : day == today.subtract(const Duration(days: 1))
        ? 'Kemarin'
        : Fmt.date(day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Expanded(child: Divider(color: EColors.line)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E7FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3730A3),
                letterSpacing: 0.2,
              ),
            ),
          ),
          const Expanded(child: Divider(color: EColors.line)),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [EColors.blue, Color(0xFF7C3AED)],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.forum_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Belum ada percakapan',
            style: TextStyle(fontWeight: FontWeight.w700, color: EColors.ink),
          ),
          const SizedBox(height: 4),
          const Text(
            'Mulai diskusi dengan mengirim pesan di bawah.',
            style: TextStyle(color: EColors.muted, fontSize: 12.5),
          ),
        ],
      ),
    ),
  );
}

/// Chat bubble. The ticket reporter (user) sits on the RIGHT in a blue
/// gradient bubble; IT Support / Admin replies sit on the LEFT in a white
/// bubble with a role badge. Internal notes are amber and always on the left.
/// A chat bubble: a comment, or a file attachment (image thumbnail / file
/// chip) shown in the timeline at the time it was uploaded.
class _CommentItem extends StatelessWidget {
  const _CommentItem(
    CommentModel this.c, {
    required this.fromReporter,
    required this.mine,
    this.onEdit,
    this.onDelete,
  }) : file = null;
  const _CommentItem.attachment(
    AttachmentModel this.file, {
    required this.fromReporter,
    required this.mine,
    this.onDelete,
  }) : c = null,
       onEdit = null;
  final CommentModel? c;
  final AttachmentModel? file;
  final bool fromReporter;
  final bool mine;

  /// Shown in the bubble's ⋯ menu when not null.
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  static const _userGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B82F6), Color(0xFF4F46E5)],
  );
  static const _badgeGradient = LinearGradient(
    colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
  );

  @override
  Widget build(BuildContext context) {
    final c = this.c;
    final file = this.file;
    final name = (c != null ? c.authorName : file!.uploaderName) ?? 'User';
    final internal = c?.isInternal ?? false;
    final createdAt = c?.createdAt ?? file!.createdAt;
    final right = fromReporter && !internal;
    const r = Radius.circular(18);
    const tail = Radius.circular(4);

    final textColor = right ? Colors.white : EColors.text;
    final metaColor = right
        ? Colors.white.withValues(alpha: 0.8)
        : EColors.muted;

    final bubble = Container(
      padding: file != null && file.isImage
          ? const EdgeInsets.fromLTRB(4, 4, 4, 6)
          : const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        gradient: right ? _userGradient : null,
        color: right
            ? null
            : internal
            ? const Color(0xFFFFFBEB)
            : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: r,
          topRight: r,
          bottomLeft: right ? r : tail,
          bottomRight: right ? tail : r,
        ),
        border: right
            ? null
            : Border.all(
                color: internal ? const Color(0xFFFCD34D) : EColors.line,
              ),
        boxShadow: [
          BoxShadow(
            color: right
                ? const Color(0xFF4F46E5).withValues(alpha: 0.25)
                : const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: right ? 14 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: right
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (internal)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 10,
                      color: Color(0xFFB45309),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'CATATAN INTERNAL',
                      style: TextStyle(
                        color: Color(0xFFB45309),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (c != null && c.isDeleted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block_rounded, size: 15, color: metaColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Pesan ini telah dihapus',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontStyle: FontStyle.italic,
                      color: metaColor,
                    ),
                  ),
                ),
              ],
            )
          else if (c != null)
            SelectionArea(
              child: Text(
                c.content,
                style: TextStyle(fontSize: 14, height: 1.45, color: textColor),
              ),
            )
          else
            _ChatAttachment(file!, onDark: right),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (file != null && file.isImage) const SizedBox(width: 6),
              if (c != null && c.isEdited && !c.isDeleted) ...[
                Text(
                  'diedit',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    color: metaColor,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                Fmt.time(createdAt),
                style: TextStyle(fontSize: 10.5, color: metaColor),
              ),
              if (mine) ...[
                const SizedBox(width: 4),
                Icon(Icons.done_all_rounded, size: 13, color: metaColor),
              ],
              if (onEdit != null || onDelete != null) ...[
                const SizedBox(width: 2),
                SizedBox(
                  width: 22,
                  height: 18,
                  child: PopupMenuButton<String>(
                    key: Key('chat_menu_${c?.id ?? file!.id}'),
                    tooltip: 'Opsi',
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: Icon(Icons.more_horiz_rounded, color: metaColor),
                    onSelected: (v) =>
                        v == 'edit' ? onEdit?.call() : onDelete?.call(),
                    itemBuilder: (_) => [
                      if (onEdit != null)
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_outlined, size: 18),
                            title: Text('Edit'),
                          ),
                        ),
                      if (onDelete != null)
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Color(0xFFDC2626),
                            ),
                            title: Text(
                              'Hapus',
                              style: TextStyle(color: Color(0xFFDC2626)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              mine ? 'Anda' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: EColors.ink,
              ),
            ),
          ),
          if (!fromReporter) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                gradient: _badgeGradient,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, size: 10, color: Colors.white),
                  SizedBox(width: 3),
                  Text(
                    'IT SUPPORT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    final Widget avatar = right
        ? InitialsAvatar(name, size: 32)
        : Stack(
            clipBehavior: Clip.none,
            children: [
              InitialsAvatar(name, size: 32),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.headset_mic_rounded,
                    size: 8,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, box) {
          final maxBubble = box.maxWidth * (box.maxWidth > 700 ? 0.62 : 0.78);
          final column = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxBubble),
            child: Column(
              crossAxisAlignment: right
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [header, bubble],
            ),
          );
          return Row(
            mainAxisAlignment: right
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: right
                ? [Flexible(child: column), const SizedBox(width: 8), avatar]
                : [avatar, const SizedBox(width: 8), Flexible(child: column)],
          );
        },
      ),
    );
  }
}

/// Attachment content inside a chat bubble: an image thumbnail (tap to view
/// full size) or a file chip (tap to download).
class _ChatAttachment extends ConsumerWidget {
  const _ChatAttachment(this.file, {required this.onDark});
  final AttachmentModel file;
  final bool onDark;

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(attachmentBytesProvider(file.id).future);
      await downloadBytes(bytes, file.fileName, file.mimeType);
    } catch (e) {
      if (context.mounted) {
        showSnack(
          context,
          'Gagal mengunduh lampiran: ${friendlyError(e)}',
          error: true,
        );
      }
    }
  }

  void _open(BuildContext context, WidgetRef ref, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      file.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Unduh',
                    icon: const Icon(Icons.download_rounded),
                    onPressed: () => _download(context, ref),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (file.isImage) {
      final bytes = ref.watch(attachmentBytesProvider(file.id));
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: bytes.when(
          data: (b) => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: Key('chat_image_${file.id}'),
              onTap: () => _open(context, ref, b),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 96,
                  minHeight: 96,
                  maxWidth: 260,
                  maxHeight: 260,
                ),
                child: Image.memory(
                  b,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _fileChip(context, ref),
                ),
              ),
            ),
          ),
          loading: () => Container(
            width: 200,
            height: 140,
            color: const Color(0xFFF1F5F9),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, _) => _fileChip(context, ref),
        ),
      );
    }
    return _fileChip(context, ref);
  }

  Widget _fileChip(BuildContext context, WidgetRef ref) {
    final fg = onDark ? Colors.white : EColors.ink;
    final sub = onDark ? Colors.white.withValues(alpha: 0.8) : EColors.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _download(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              file.isImage
                  ? Icons.image_outlined
                  : Icons.insert_drive_file_outlined,
              color: fg,
              size: 22,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: fg,
                    ),
                  ),
                  Text(
                    '${file.displaySize} · ketuk untuk unduh',
                    style: TextStyle(fontSize: 11, color: sub),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
/// Lampiran tab: list attachments with download links + upload (mockup 9).
class _AttachmentsTab extends ConsumerStatefulWidget {
  const _AttachmentsTab({super.key, required this.ticket, required this.user});
  final TicketModel ticket;
  final UserModel user;

  @override
  ConsumerState<_AttachmentsTab> createState() => _AttachmentsTabState();
}

class _AttachmentsTabState extends ConsumerState<_AttachmentsTab> {
  bool _busy = false;
  String? _statusMessage;
  bool _statusError = false;

  void _setStatus(String? message, {bool error = false}) {
    setState(() {
      _statusMessage = message;
      _statusError = error;
    });
  }

  Future<void> _pickAndUpload() async {
    final picked = await pickFile();
    if (picked == null) return;

    final (fileName, mimeType, bytes) = picked;
    if (bytes.length > kMaxAttachmentDisplaySize) {
      _setStatus('File terlalu besar (maks 10 MB).', error: true);
      return;
    }

    setState(() => _busy = true);
    _setStatus(null);
    try {
      await ref
          .read(attachmentActionsProvider)
          .uploadAttachment(
            ticketId: widget.ticket.id,
            fileName: fileName,
            mimeType: mimeType,
            bytes: bytes,
            uploadedBy: widget.user.id,
          );
      _setStatus('Lampiran terunggah.');
    } catch (e) {
      _setStatus('Gagal mengunggah: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachments = ref.watch(attachmentsProvider(widget.ticket.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Lampiran',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: EColors.ink,
                  ),
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                OutlinedButton.icon(
                  key: const Key('upload_attachment_button'),
                  onPressed: _pickAndUpload,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: const Text('Unggah'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          attachments.when(
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(0, 40, 0, 24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.attach_file_rounded,
                            size: 44,
                            color: EColors.grey,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Belum ada lampiran.',
                            style: TextStyle(color: EColors.muted),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Maks 10 MB · JPG, PNG, PDF',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: EColors.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (final a in list) _AttachmentItem(attachment: a),
                    ],
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Center(child: Text('Gagal memuat lampiran: $e')),
          ),
          const SizedBox(height: 8),
          const Text(
            'Catatan: Lampiran hanya dapat diakses oleh pengguna yang dapat melihat tiket ini '
            '(atas RLS basis data). File disimpan di folder Google Drive IT Support, tidak tersedia untuk publik.',
            style: TextStyle(color: EColors.muted, fontSize: 11, height: 1.5),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusError
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _statusError
                      ? const Color(0xFFFECACA)
                      : const Color(0xFFBBF7D0),
                ),
              ),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  color: _statusError
                      ? const Color(0xFF991B1B)
                      : const Color(0xFF15803D),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentItem extends ConsumerWidget {
  const _AttachmentItem({required this.attachment});
  final AttachmentModel attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = attachment;
    final isImage = a.isImage;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isImage ? EColors.blueSoft : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
              color: isImage ? EColors.blue : EColors.muted,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: EColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${a.displaySize} · ${Fmt.dateTime(a.createdAt)}',
                  style: const TextStyle(fontSize: 11.5, color: EColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Unduh',
            icon: const Icon(Icons.download_rounded, color: EColors.blue),
            onPressed: () async {
              try {
                final bytes = await ref
                    .read(attachmentActionsProvider)
                    .downloadAttachment(a.id);
                await downloadBytes(bytes, a.fileName, a.mimeType);
              } catch (e) {
                if (context.mounted) {
                  showSnack(
                    context,
                    'Gagal mengunduh lampiran: ${friendlyError(e)}',
                    error: true,
                  );
                }
              }
            },
          ),
        ],
      ),
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
  ActivityModel.actionCreated => EColors.blue,
  ActivityModel.actionAssigned => const Color(0xFF7C3AED),
  ActivityModel.actionResolved => const Color(0xFF10B981),
  ActivityModel.actionReopened => const Color(0xFFEF4444),
  ActivityModel.actionClosed => const Color(0xFF6B7280),
  _ => const Color(0xFFF59E0B),
};

String describeActivity(ActivityModel a) {
  final who = a.actorName ?? 'Sistem';
  return switch (a.action) {
    ActivityModel.actionCreated => 'Tiket dibuat oleh $who',
    ActivityModel.actionAssigned =>
      a.newValue == null
          ? 'Tiket dicabut dari penugasan oleh $who'
          : 'Tiket ditugaskan oleh $who',
    ActivityModel.actionResolved => 'Tiket diselesaikan oleh $who',
    ActivityModel.actionReopened => 'Tiket dibuka ulang oleh $who',
    ActivityModel.actionClosed => 'Tiket ditutup oleh $who',
    ActivityModel.actionPriorityChanged =>
      'Prioritas ${Fmt.priority(a.oldValue)} → ${Fmt.priority(a.newValue)} oleh $who',
    ActivityModel.actionCategoryChanged =>
      'Kategori ${a.oldValue} → ${a.newValue} oleh $who',
    _ =>
      'Status ${Fmt.statusId(a.oldValue)} → ${Fmt.statusId(a.newValue)} oleh $who',
  };
}
