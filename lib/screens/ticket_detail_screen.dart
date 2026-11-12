import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
import '../models/activity_model.dart';
import '../models/comment_model.dart';
import '../models/ticket_model.dart';
import '../models/ticket_stats.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/tickets_provider.dart';
import '../utils/error_messages.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/employee_ui.dart';

/// "7.–9. Detail Tiket" of the design: coloured header, progress
/// (Dibuat → Diproses → Selesai) and tabs Detail / Komentar / Lampiran.
/// IT Support additionally gets the workflow actions in the Detail tab.
class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({super.key, required this.ticketId});
  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(ticketDetailProvider(ticketId));
    final user = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      backgroundColor: EColors.page,
      appBar: EHeader(
        title: 'Detail Tiket',
        onBack: () => goBack(context, fallback: '/tickets'),
      ),
      body: detail.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(ticketDetailProvider(ticketId)),
        ),
        data: (d) {
          if (user == null) return const LoadingView();
          final visibleComments = user.isStaff
              ? d.comments
              : d.comments.where((c) => !c.isInternal).toList();
          return DefaultTabController(
            length: 3,
            child: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      children: [
                        _Header(ticket: d.ticket),
                        const SizedBox(height: 12),
                        _Progress(detail: d),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabsHeader(commentCount: visibleComments.length),
                ),
              ],
              body: TabBarView(
                children: [
                  _DetailTab(detail: d, user: user),
                  _CommentsTab(
                    detail: d,
                    user: user,
                    comments: visibleComments,
                  ),
                  const _AttachmentsTab(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _Header extends StatelessWidget {
  const _Header({required this.ticket});
  final TicketModel ticket;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final tint = EColors.priority(t.priority);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(tint.withValues(alpha: 0.08), Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.18)),
      ),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.ticketNumber,
                    style: TextStyle(
                      color: tint,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                ETag.priority(t.priority),
                const SizedBox(width: 6),
                ETag.status(t.status),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              t.subject,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: EColors.ink,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t.description,
              style: const TextStyle(
                color: EColors.text,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dibuat → Diproses → Selesai with the moment each step was reached.
class _Progress extends StatelessWidget {
  const _Progress({required this.detail});
  final TicketDetail detail;

  DateTime? get _startedAt {
    for (final a in detail.activities) {
      final started =
          (a.action == ActivityModel.actionAssigned && a.newValue != null) ||
          (a.action == ActivityModel.actionStatusChanged &&
              (a.newValue == AppConstants.statusInProgress ||
                  a.newValue == AppConstants.statusAssigned));
      if (started) return a.createdAt;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = detail.ticket;
    final started =
        _startedAt ??
        (t.status != AppConstants.statusOpen ? t.updatedAt : null);
    final done = t.resolvedAt ?? t.closedAt;
    final steps = [
      ('Dibuat', t.createdAt),
      ('Diproses', t.status == AppConstants.statusOpen ? null : started),
      ('Selesai', t.isFinished ? done : null),
    ];
    return ECard(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Expanded(
              child: _ProgressNode(
                label: steps[i].$1,
                at: steps[i].$2,
                reached: steps[i].$2 != null,
                alignment: i == 0
                    ? CrossAxisAlignment.start
                    : (i == steps.length - 1
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.center),
                lineBefore: i > 0 ? steps[i].$2 != null : null,
                lineAfter: i < steps.length - 1
                    ? steps[i + 1].$2 != null
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressNode extends StatelessWidget {
  const _ProgressNode({
    required this.label,
    required this.at,
    required this.reached,
    required this.alignment,
    this.lineBefore,
    this.lineAfter,
  });
  final String label;
  final DateTime? at;
  final bool reached;
  final CrossAxisAlignment alignment;
  final bool? lineBefore;
  final bool? lineAfter;

  @override
  Widget build(BuildContext context) {
    Widget line(bool? on) => on == null
        ? const Spacer()
        : Expanded(
            child: Container(
              height: 2,
              color: on ? EColors.blue : EColors.line,
            ),
          );
    final dot = Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: reached ? EColors.blue : EColors.grey,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: reached
          ? Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: EColors.blue,
              ),
            )
          : null,
    );
    final textAlign = switch (alignment) {
      CrossAxisAlignment.start => TextAlign.left,
      CrossAxisAlignment.end => TextAlign.right,
      _ => TextAlign.center,
    };
    return Semantics(
      label: '$label: ${at == null ? 'belum' : Fmt.dateTime(at!)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          SizedBox(
            height: 18,
            child: Row(
              children: [
                if (alignment != CrossAxisAlignment.start) line(lineBefore),
                dot,
                if (alignment != CrossAxisAlignment.end) line(lineAfter),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: textAlign,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: reached ? EColors.ink : EColors.muted,
            ),
          ),
          Text(
            at == null ? '-' : Fmt.dateTime(at!),
            textAlign: textAlign,
            style: const TextStyle(fontSize: 11, color: EColors.muted),
          ),
        ],
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({required this.commentCount});
  final int commentCount;

  @override
  double get minExtent => 60;
  @override
  double get maxExtent => 60;

  @override
  bool shouldRebuild(_TabsHeader old) => old.commentCount != commentCount;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    Widget tab(String label, int? count) => Tab(
      height: 40,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: const TextStyle(fontSize: 11, color: EColors.text),
              ),
            ),
          ],
        ],
      ),
    );
    return Container(
      color: EColors.page,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: EColors.line),
        ),
        child: TabBar(
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: EColors.blueSoft,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFBFD4FE)),
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          labelColor: EColors.blue,
          unselectedLabelColor: EColors.text,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          tabs: [
            tab('Detail', null),
            tab('Komentar', commentCount),
            tab('Lampiran', 0),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
/// Detail tab: information, resolution, actions and history.
class _DetailTab extends StatelessWidget {
  const _DetailTab({required this.detail, required this.user});
  final TicketDetail detail;
  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final t = detail.ticket;
    final info = <(IconData, Color, String, String)>[
      (categoryStyle(t.category).$1, EColors.blue, 'Kategori', t.category),
      (
        Icons.error_rounded,
        EColors.priority(t.priority),
        'Prioritas',
        Fmt.priority(t.priority),
      ),
      (
        Icons.flag_outlined,
        EColors.status(t.status),
        'Status',
        Fmt.statusId(t.status),
      ),
      (
        Icons.support_agent,
        EColors.purple,
        'Ditangani oleh',
        t.assigneeName ?? 'Belum ditugaskan',
      ),
      (Icons.person_outline, EColors.teal, 'Pelapor', t.reporterName ?? '—'),
      (Icons.schedule, EColors.muted, 'Diperbarui', Fmt.dateTime(t.updatedAt)),
    ];
    final history = [...detail.activities]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        ECard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Informasi',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: EColors.ink,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final w = (c.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 14,
                    children: [
                      for (final (icon, color, label, value) in info)
                        SizedBox(
                          width: w,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(icon, size: 20, color: color),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: EColors.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      value,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: EColors.ink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        if (t.resolution != null && t.resolution!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF86EFAC)),
            ),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Penyelesaian',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF15803D),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(t.resolution!),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (user.isStaff)
          _StaffActions(ticket: t, user: user)
        else if (t.reporterId == user.id)
          _ReporterActions(ticket: t),
        const SizedBox(height: 12),
        ECard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Riwayat',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: EColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Belum ada aktivitas.',
                    style: TextStyle(color: EColors.muted),
                  ),
                ),
              for (final a in history) _ActivityItem(a),
            ],
          ),
        ),
      ],
    );
  }
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

class _StaffActionsState extends ConsumerState<_StaffActions>
    with _ActionRunner {
  TicketActions get _actions => ref.read(ticketActionsProvider);
  TicketModel get t => widget.ticket;

  static const _statusLabels = {
    AppConstants.statusInProgress: ('Start work', Icons.play_arrow),
    AppConstants.statusPendingUser: (
      'Waiting for user',
      Icons.hourglass_bottom,
    ),
    AppConstants.statusResolved: ('Resolve', Icons.check_circle),
    AppConstants.statusClosed: ('Close', Icons.lock),
    AppConstants.statusReopened: ('Reopen', Icons.replay),
    AppConstants.statusOpen: ('Return to queue', Icons.undo),
  };

  Future<void> _changeStatus(String status) async {
    String? resolution;
    if (status == AppConstants.statusResolved ||
        (status == AppConstants.statusClosed &&
            (t.resolution ?? '').trim().isEmpty)) {
      resolution = await showTextInputDialog(
        context,
        title: status == AppConstants.statusResolved
            ? 'Resolve ticket'
            : 'Close ticket',
        label: status == AppConstants.statusResolved
            ? 'What was done to resolve it? (visible to the employee)'
            : 'Reason for closing (e.g. duplicate of ITSR-00012)',
        confirmLabel: status == AppConstants.statusResolved
            ? 'Resolve'
            : 'Close',
        initialValue: t.resolution,
        minLength: 5,
      );
      if (resolution == null) return;
    } else {
      final ok = await showConfirmDialog(
        context,
        title: 'Change status',
        message:
            'Change ${t.ticketNumber} from "${Fmt.status(t.status)}" to "${Fmt.status(status)}"? '
            'The reporter will be notified by email.',
        confirmLabel: _statusLabels[status]?.$1 ?? 'Confirm',
      );
      if (!ok) return;
    }
    await run(
      () => _actions.changeStatus(t.id, status, resolution: resolution),
      'Status updated to ${Fmt.status(status)}',
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
        title: const Text('Assign ticket to'),
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
      'Assigned to ${chosen.fullName}',
    );
  }

  Future<void> _priority(String? p) async {
    if (p == null || p == t.priority) return;
    await run(
      () => _actions.changePriority(t.id, p),
      'Priority set to ${Fmt.priority(p)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final next = AppConstants.staffTransitions[t.status] ?? const [];
    final mine = t.assignedToId == widget.user.id;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'IT Support actions',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
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
                            'You are now assigned to this ticket',
                          ),
                    icon: const Icon(Icons.pan_tool_alt),
                    label: Text(
                      t.assignedToId == null ? 'Accept ticket' : 'Take over',
                    ),
                  ),
                if (!t.isFinished)
                  OutlinedButton.icon(
                    onPressed: busy ? null : _assign,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Assign to…'),
                  ),
                for (final s in next)
                  OutlinedButton.icon(
                    key: Key('status_$s'),
                    onPressed: busy ? null : () => _changeStatus(s),
                    icon: Icon(_statusLabels[s]?.$2 ?? Icons.sync_alt),
                    label: Text(_statusLabels[s]?.$1 ?? Fmt.status(s)),
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
                  labelText: 'Priority',
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
                      title: 'Konfirmasi & tutup',
                      message:
                          'Tutup ${t.ticketNumber}? Anda masih bisa membukanya kembali jika masalah muncul lagi.',
                      confirmLabel: 'Tutup tiket',
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
        message = 'IT Support menunggu informasi dari Anda. Silakan balas melalui tab Komentar.';
      default:
        message = 'IT Support akan memperbarui tiket ini selama penanganan. Anda akan mendapat notifikasi email.';
    }
    if (t.isFinished) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final reason = await showTextInputDialog(
                    context,
                    title: 'Buka ulang tiket',
                    label: 'Mengapa masalah belum teratasi?',
                    confirmLabel: 'Buka Ulang',
                    minLength: 5,
                  );
                  if (reason != null) {
                    await run(
                      () => actions.reopen(t.id, reason),
                      'Tiket dibuka ulang. IT Support sudah diberi tahu.',
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
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_rounded, color: EColors.blue),
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
/// Comments tab: conversation + composer pinned at the bottom.
class _CommentsTab extends ConsumerStatefulWidget {
  const _CommentsTab({
    required this.detail,
    required this.user,
    required this.comments,
  });
  final TicketDetail detail;
  final UserModel user;
  final List<CommentModel> comments;

  @override
  ConsumerState<_CommentsTab> createState() => _CommentsTabState();
}

class _CommentsTabState extends ConsumerState<_CommentsTab> with _ActionRunner {
  final _text = TextEditingController();
  bool _internal = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final content = _text.text.trim();
    if (content.isEmpty) {
      showSnack(context, 'Tulis komentar terlebih dahulu', error: true);
      return;
    }
    await run(() async {
      await ref
          .read(ticketActionsProvider)
          .addComment(widget.detail.ticket.id, content, isInternal: _internal);
      _text.clear();
      setState(() => _internal = false);
    }, _internal ? 'Catatan internal ditambahkan' : 'Komentar terkirim');
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.user.isStaff;
    final comments = [...widget.comments]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final closed =
        widget.detail.ticket.status == AppConstants.statusClosed && !staff;
    return Column(
      children: [
        Expanded(
          child: comments.isEmpty
              ? const EmptyView(
                  icon: Icons.chat_bubble_outline,
                  title: 'Belum ada komentar',
                  message: 'Tulis komentar untuk berdiskusi dengan IT Support.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: comments.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _CommentItem(comments[i]),
                ),
        ),
        if (!closed)
          Material(
            color: Colors.white,
            shape: const Border(top: BorderSide(color: EColors.line)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (staff)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _internal,
                        onChanged: busy
                            ? null
                            : (v) => setState(() => _internal = v ?? false),
                        title: const Text('Internal work note'),
                        subtitle: const Text(
                          'Hanya terlihat oleh IT Support & Administrator; tanpa email',
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('comment_field'),
                            controller: _text,
                            enabled: !busy,
                            minLines: 1,
                            maxLines: 5,
                            maxLength: 5000,
                            decoration:
                                eInput(
                                  hint: 'Tulis komentar...',
                                  counter: '',
                                ).copyWith(
                                  suffixIcon: const Tooltip(
                                    message: 'Lampiran belum tersedia',
                                    child: Icon(
                                      Icons.attach_file,
                                      color: EColors.grey,
                                    ),
                                  ),
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: FilledButton(
                              key: const Key('post_comment_button'),
                              onPressed: busy ? null : _post,
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor: EColors.blue,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: busy
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
                                      semanticLabel: 'Kirim komentar',
                                    ),
                            ),
                          ),
                        ),
                      ],
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

class _ActivityItem extends StatelessWidget {
  const _ActivityItem(this.a);
  final ActivityModel a;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(activityIcon(a.action), color: activityColor(a.action), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                describeActivityId(a),
                style: const TextStyle(color: EColors.ink, fontSize: 13.5),
              ),
              Text(
                Fmt.dateTime(a.createdAt),
                style: const TextStyle(fontSize: 11.5, color: EColors.muted),
              ),
              if (a.note != null && a.note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '“${a.note}”',
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
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
    final name = c.authorName ?? 'Pengguna';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.isInternal ? const Color(0xFFFEF3C7) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: c.isInternal ? const Color(0xFFFDE047) : EColors.line,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InitialsAvatar(name, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: EColors.ink,
                      ),
                    ),
                    Text(
                      Fmt.dateTime(c.createdAt),
                      style: const TextStyle(
                        color: EColors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                    if (c.isInternal)
                      const Text(
                        'INTERNAL NOTE',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                SelectionArea(
                  child: Text(
                    c.content,
                    style: const TextStyle(color: EColors.text, height: 1.4),
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
/// Attachments tab (upload is not available yet).
class _AttachmentsTab extends StatelessWidget {
  const _AttachmentsTab();

  @override
  Widget build(BuildContext context) => const EmptyView(
    icon: Icons.attach_file,
    title: 'Belum ada lampiran',
    message: 'Upload lampiran belum tersedia. Kirim detail atau permintaan foto melalui komentar.',
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

/// Indonesian history line for the ticket detail ("Riwayat").
String describeActivityId(ActivityModel a) {
  final who = a.actorName ?? 'Sistem';
  return switch (a.action) {
    ActivityModel.actionCreated => 'Tiket dibuat oleh $who',
    ActivityModel.actionAssigned =>
      a.newValue == null
          ? 'Tiket dikembalikan ke antrean oleh $who'
          : 'Tiket ditangani oleh $who',
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
