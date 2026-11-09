import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
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
import 'dashboard_screen.dart' show activityColor, activityIcon, describeActivity;

class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({super.key, required this.ticketId});
  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(ticketDetailProvider(ticketId));
    final user = ref.watch(currentUserProvider).valueOrNull;

    return detail.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(ticketDetailProvider(ticketId)),
      ),
      data: (d) {
        if (user == null) return const LoadingView();
        final wide = MediaQuery.sizeOf(context).width >= 1100;
        final main = [
          _Header(ticket: d.ticket),
          const SizedBox(height: 16),
          if (user.isStaff) ...[
            _StaffActions(ticket: d.ticket, user: user),
            const SizedBox(height: 16),
          ] else if (d.ticket.reporterId == user.id) ...[
            _ReporterActions(ticket: d.ticket),
            const SizedBox(height: 16),
          ],
        ];
        final side = [
          _CommentBox(ticket: d.ticket, user: user),
          const SizedBox(height: 16),
          _Timeline(detail: d),
        ];
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(ticketDetailProvider(ticketId)),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PageBody(
                maxWidth: 1300,
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: Column(children: main)),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: Column(children: side)),
                        ],
                      )
                    : Column(children: [...main, ...side]),
              ),
            ],
          ),
        );
      },
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
    final meta = <(String, String)>[
      ('Category', t.category),
      ('Priority', Fmt.priority(t.priority)),
      ('Reporter', t.reporterName ?? '—'),
      ('Assigned to', t.assigneeName ?? 'Unassigned'),
      ('Created', Fmt.dateTime(t.createdAt)),
      ('Last update', Fmt.dateTime(t.updatedAt)),
      if (t.resolvedAt != null) ('Resolved', Fmt.dateTime(t.resolvedAt!)),
      if (t.closedAt != null) ('Closed', Fmt.dateTime(t.closedAt!)),
    ];
    // Text + SelectionArea (not SelectableText): stays selectable for copying
    // ticket numbers, and is exposed to screen readers. SelectableText content
    // was announced as empty edit fields on Flutter Web (Phase 16 E2E finding).
    return Card(
      margin: EdgeInsets.zero,
      child: SelectionArea(
        child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(t.ticketNumber,
                    style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold)),
                StatusChip(t.status),
                PriorityChip(t.priority),
              ],
            ),
            const SizedBox(height: 12),
            Text(t.subject,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                for (final (label, value) in meta)
                  SizedBox(
                    width: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(height: 32),
            Text('Description', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(t.description),
            if (t.resolution != null && t.resolution!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resolution',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.green[800])),
                    const SizedBox(height: 4),
                    Text(t.resolution!),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      ),
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

class _StaffActionsState extends ConsumerState<_StaffActions> with _ActionRunner {
  TicketActions get _actions => ref.read(ticketActionsProvider);
  TicketModel get t => widget.ticket;

  static const _statusLabels = {
    AppConstants.statusInProgress: ('Start work', Icons.play_arrow),
    AppConstants.statusPendingUser: ('Waiting for user', Icons.hourglass_bottom),
    AppConstants.statusResolved: ('Resolve', Icons.check_circle),
    AppConstants.statusClosed: ('Close', Icons.lock),
    AppConstants.statusReopened: ('Reopen', Icons.replay),
    AppConstants.statusOpen: ('Return to queue', Icons.undo),
  };

  Future<void> _changeStatus(String status) async {
    String? resolution;
    if (status == AppConstants.statusResolved ||
        (status == AppConstants.statusClosed && (t.resolution ?? '').trim().isEmpty)) {
      resolution = await showTextInputDialog(
        context,
        title: status == AppConstants.statusResolved ? 'Resolve ticket' : 'Close ticket',
        label: status == AppConstants.statusResolved
            ? 'What was done to resolve it? (visible to the employee)'
            : 'Reason for closing (e.g. duplicate of ITSR-00012)',
        confirmLabel: status == AppConstants.statusResolved ? 'Resolve' : 'Close',
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
    await run(() => _actions.changeStatus(t.id, status, resolution: resolution),
        'Status updated to ${Fmt.status(status)}');
  }

  Future<void> _assign() async {
    final staff = await ref.read(assignableStaffProvider.future).catchError((Object e) {
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
                leading: Icon(s.id == t.assignedToId ? Icons.radio_button_checked : Icons.person_outline),
                title: Text(s.fullName),
                subtitle: Text('${s.employeeNumber} • ${Fmt.role(s.role)}'),
              ),
            ),
        ],
      ),
    );
    if (chosen == null || chosen.id == t.assignedToId) return;
    await run(() => _actions.assignTicket(t.id, chosen.id), 'Assigned to ${chosen.fullName}');
  }

  Future<void> _priority(String? p) async {
    if (p == null || p == t.priority) return;
    await run(() => _actions.changePriority(t.id, p), 'Priority set to ${Fmt.priority(p)}');
  }

  @override
  Widget build(BuildContext context) {
    final next = AppConstants.staffTransitions[t.status] ?? const [];
    final mine = t.assignedToId == widget.user.id;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('IT Support actions',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
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
                        : () => run(() => _actions.acceptTicket(t.id), 'You are now assigned to this ticket'),
                    icon: const Icon(Icons.pan_tool_alt),
                    label: Text(t.assignedToId == null ? 'Accept ticket' : 'Take over'),
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
                decoration: const InputDecoration(labelText: 'Priority', isDense: true),
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

class _ReporterActionsState extends ConsumerState<_ReporterActions> with _ActionRunner {
  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final actions = ref.read(ticketActionsProvider);
    final String message;
    final List<Widget> buttons = [];

    switch (t.status) {
      case AppConstants.statusResolved:
        message = 'IT Support marked this ticket as resolved. Is your problem fixed?';
        buttons.add(FilledButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final ok = await showConfirmDialog(context,
                      title: 'Confirm and close',
                      message: 'Close ${t.ticketNumber}? You can still reopen it later if the problem returns.',
                      confirmLabel: 'Close ticket');
                  if (ok) await run(() => actions.confirmClose(t.id), 'Ticket closed. Thank you!');
                },
          icon: const Icon(Icons.check),
          label: const Text('Yes, close ticket'),
        ));
      case AppConstants.statusClosed:
        message = 'This ticket is closed.';
      case AppConstants.statusPendingUser:
        message = 'IT Support is waiting for information from you. Please reply with a comment below.';
      default:
        message = 'IT Support will update this ticket as work progresses. You will be notified by email.';
    }
    if (t.isFinished) {
      buttons.add(OutlinedButton.icon(
        onPressed: busy
            ? null
            : () async {
                final reason = await showTextInputDialog(context,
                    title: 'Reopen ticket',
                    label: 'Why is the problem not solved?',
                    confirmLabel: 'Reopen',
                    minLength: 5);
                if (reason != null) {
                  await run(() => actions.reopen(t.id, reason), 'Ticket reopened. IT Support has been notified.');
                }
              },
        icon: const Icon(Icons.replay),
        label: const Text('Reopen'),
      ));
    }

    return Card(
      margin: EdgeInsets.zero,
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info_outline, color: Colors.blue[800]),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ]),
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
class _CommentBox extends ConsumerStatefulWidget {
  const _CommentBox({required this.ticket, required this.user});
  final TicketModel ticket;
  final UserModel user;

  @override
  ConsumerState<_CommentBox> createState() => _CommentBoxState();
}

class _CommentBoxState extends ConsumerState<_CommentBox> with _ActionRunner {
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
      showSnack(context, 'Please write a comment first', error: true);
      return;
    }
    await run(() async {
      await ref.read(ticketActionsProvider).addComment(widget.ticket.id, content, isInternal: _internal);
      _text.clear();
      setState(() => _internal = false);
    }, _internal ? 'Internal note added' : 'Comment posted');
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.user.isStaff;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a comment', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              key: const Key('comment_field'),
              controller: _text,
              enabled: !busy,
              minLines: 3,
              maxLines: 8,
              maxLength: 5000,
              decoration: InputDecoration(
                hintText: staff
                    ? 'Reply to the employee, or add a technical note'
                    : 'Add details or reply to IT Support',
              ),
            ),
            if (staff)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _internal,
                onChanged: busy ? null : (v) => setState(() => _internal = v ?? false),
                title: const Text('Internal work note'),
                subtitle: const Text('Only visible to IT Support and Administrators; no email is sent'),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('post_comment_button'),
                onPressed: busy ? null : _post,
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_internal ? 'Add note' : 'Post comment'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.detail});
  final TicketDetail detail;

  @override
  Widget build(BuildContext context) {
    final events = <(DateTime, Widget)>[
      for (final a in detail.activities) (a.createdAt, _ActivityItem(a)),
      for (final c in detail.comments) (c.createdAt, _CommentItem(c)),
    ]..sort((x, y) => y.$1.compareTo(x.$1)); // newest first

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('History & comments', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No activity yet.'),
              ),
            for (final e in events) e.$2,
          ],
        ),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  const _ActivityItem(this.a);
  final ActivityModel a;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(activityIcon(a.action), color: activityColor(a.action)),
        title: Text('Ticket ${describeActivity(a)}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Fmt.dateTime(a.createdAt), style: const TextStyle(fontSize: 12)),
            if (a.note != null && a.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('“${a.note}”', style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      );
}

class _CommentItem extends StatelessWidget {
  const _CommentItem(this.c);
  final CommentModel c;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.isInternal ? Colors.amber[50] : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: c.isInternal ? Border.all(color: Colors.amber[300]!) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.chat_bubble_outline, size: 16),
                Text(c.authorName ?? 'User', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(Fmt.dateTime(c.createdAt), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                if (c.isInternal)
                  Text('INTERNAL NOTE',
                      style: TextStyle(
                          color: Colors.amber[900], fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            SelectionArea(child: Text(c.content)),
          ],
        ),
      );
}
