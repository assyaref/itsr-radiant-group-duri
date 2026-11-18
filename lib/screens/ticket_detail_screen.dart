import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../utils/browser_files.dart' show downloadBytes;
import '../utils/error_messages.dart';
import '../utils/formatters.dart';
import '../utils/file_picker_web.dart' if (dart.library.io) '../utils/file_picker_stub.dart';
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
  ConsumerState<TicketDetailScreen> createState() =>
      _TicketDetailScreenState();
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
          onRetry: () =>
              ref.invalidate(ticketDetailProvider(widget.ticketId)),
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
        'critical' || 'high' => (
            const Color(0xFFFEF2F2),
            EColors.red,
          ),
        'medium' => (
            const Color(0xFFFFFBEB),
            const Color(0xFFD97706),
          ),
        'low' => (
            const Color(0xFFF0FDF4),
            const Color(0xFF16A34A),
          ),
        _ => (EColors.blueSoft, EColors.blue),
      };

  bool get _processedReached {
    if (const ['assigned', 'in_progress', 'pending_user'].contains(
      ticket.status,
    )) {
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
      if (t.resolvedAt != null) ('Diproses selesai', Fmt.dateTime(t.resolvedAt!)),
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
                  Text(
                    t.resolution!,
                    style: const TextStyle(height: 1.4),
                  ),
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

class _StaffActions extends ConsumerStatefulWidget {
  const _StaffActions({required this.ticket, required this.user});
  final TicketModel ticket;
  final UserModel user;

  @override
  ConsumerState<_StaffActions> createState() => _StaffActionsState();
}

class _StaffActionsState extends ConsumerState<_StaffActions> with _ActionRunner {
  TicketActions get _actions => ref.read(ticketActionsProvider);
  TicketModel get t => widget.ticket;

  static const _statusLabels = {
    AppConstants.statusInProgress: ('Mulai Kerjakan', Icons.play_arrow),
    AppConstants.statusPendingUser: ('Menunggu Pengguna', Icons.hourglass_bottom),
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
                subtitle: Text(
                  '${s.employeeNumber} • ${Fmt.role(s.role)}',
                ),
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
        message =
            'IT Support menandai tiket ini selesai. Apakah masalah Anda sudah teratasi?';
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
        message =
            'IT Support menunggu informasi dari Anda. Silakan balas lewat tab Komentar.';
      default:
        message =
            'IT Support akan memperbarui tiket ini; Anda akan diberitahu lewat email.';
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

  @override
  void dispose() {
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
        await ref.read(attachmentActionsProvider).uploadAttachment(
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
        await ref.read(ticketActionsProvider).addComment(
          widget.detail.ticket.id,
          content,
          isInternal: _internal,
        );
        _text.clear();
      }
      setState(() => _internal = false);
    }, _internal ? 'Catatan internal ditambahkan' : 'Komentar terkirim');
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.user.isStaff;
    final events = <(DateTime, Widget)>[
      for (final a in widget.detail.activities) (a.createdAt, _ActivityItem(a)),
      for (final c in widget.detail.comments) (c.createdAt, _CommentItem(c)),
    ]..sort((x, y) => y.$1.compareTo(x.$1)); // newest first

    // Chat layout: history scrolls on top, the composer stays pinned below.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (events.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'Belum ada aktivitas.',
                        style: TextStyle(color: EColors.muted),
                      ),
                    ),
                  )
                else
                  for (final e in events) e.$2,
              ],
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
                                ? 'Balas ke pelapor, atau tulis catatan teknis'
                                : 'Tambah detail atau balas IT Support',
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
                        onPressed: busy ? null : () async {
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
                        tooltip: 'Lampirkan file',
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

/// Compact system line for an activity event (created/assigned/resolved/...).
class _ActivityItem extends StatelessWidget {
  const _ActivityItem(this.a);
  final ActivityModel a;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: activityColor(a.action).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            activityIcon(a.action),
            size: 15,
            color: activityColor(a.action),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 13,
                    color: EColors.text,
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(
                      text: describeActivity(a),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: EColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                Fmt.dateTime(a.createdAt),
                style: const TextStyle(fontSize: 11, color: EColors.muted),
              ),
              if (a.note != null && a.note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '“${a.note}”',
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 12.5,
                      color: EColors.text,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CommentItem extends StatelessWidget {
  const _CommentItem(this.c);
  final CommentModel c;

  @override
  Widget build(BuildContext context) {
    final name = c.authorName ?? 'User';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InitialsAvatar(name, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: EColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      Fmt.dateTime(c.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: EColors.muted,
                      ),
                    ),
                    if (c.isInternal) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'CATATAN INTERNAL',
                          style: TextStyle(
                            color: Color(0xFFB45309),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.isInternal
                        ? const Color(0xFFFFFBEB)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: c.isInternal
                          ? const Color(0xFFFDE68A)
                          : EColors.line,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: SelectionArea(
                      child: Text(
                        c.content,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: EColors.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
      await ref.read(attachmentActionsProvider).uploadAttachment(
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
            error: (e, _) => Center(
              child: Text('Gagal memuat lampiran: $e'),
            ),
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
              color: isImage
                  ? EColors.blueSoft
                  : const Color(0xFFF1F5F9),
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
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: EColors.muted,
                  ),
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
    _ => 'Status ${Fmt.statusId(a.oldValue)} → ${Fmt.statusId(a.newValue)} oleh $who',
  };
}
