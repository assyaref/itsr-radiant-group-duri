import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
import '../models/activity_model.dart';
import '../models/attachment_model.dart';
import '../models/comment_model.dart';
import '../models/ticket_model.dart';
import '../models/ticket_stats.dart';
import '../models/user_model.dart';
import '../providers/attachment_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/tickets_provider.dart';
import '../utils/error_messages.dart';
import '../utils/formatters.dart';
import '../utils/file_picker_web.dart' if (dart.library.io) '../utils/file_picker_stub.dart';
import '../widgets/common.dart';

const int kMaxAttachmentDisplaySize = 10 * 1024 * 1024; // 10 MiB

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
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Detail Tiket'),
          centerTitle: false,
          elevation: 0,
          bottom: TabBar(
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.muted,
            indicatorColor: AppTheme.primary,
            tabs: const [
              Tab(text: 'Detail'),
              Tab(text: 'Komentar'),
              Tab(text: 'Lampiran'),
              Tab(text: 'Unggah'),
            ],
          ),
        ),
        body: _KeyboardAvoidingTabBarView(children: [
          _DetailTab(ticket: d.ticket, user: user),
          _CommentsTab(detail: d, user: user),
          _AttachmentsTab(ticket: d.ticket),
          _UploadTab(ticket: d.ticket, user: user),
        ]),
      ),
    );
      },
    );
  }
}

// ---------------------------------------------------------------------------
/// Detail tab: header meta + actions.
class _DetailTab extends StatelessWidget {
  const _DetailTab({required this.ticket, required this.user});
  final TicketModel ticket;
  final UserModel user;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(ticket: ticket),
          const SizedBox(height: 16),
          if (user.isStaff) ...[
            _StaffActions(ticket: ticket, user: user),
            const SizedBox(height: 16),
          ] else if (ticket.reporterId == user.id) ...[
            _ReporterActions(ticket: ticket),
            const SizedBox(height: 16),
          ],
        ],
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
    final meta = <(String, String)>[
      ('Category', t.category),
      ('Priority', Fmt.priority(t.priority)),
      ('Reporter', t.reporterName ?? 'â€”'),
      ('Assigned to', t.assigneeName ?? 'Unassigned'),
      ('Created', Fmt.dateTime(t.createdAt)),
      ('Last update', Fmt.dateTime(t.updatedAt)),
      if (t.resolvedAt != null) ('Resolved', Fmt.dateTime(t.resolvedAt!)),
      if (t.closedAt != null) ('Closed', Fmt.dateTime(t.closedAt!)),
    ];
    return Card(
      elevation: 0,
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
                      style: TextStyle(
                          color: AppTheme.muted, fontWeight: FontWeight.bold)),
                  StatusChip(t.status),
                  PriorityChip(t.priority),
                ],
              ),
              const SizedBox(height: 12),
              Text(t.subject,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
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
                          Text(label,
                              style: TextStyle(
                                  color: AppTheme.muted, fontSize: 12)),
                          Text(value,
                              style: const TextStyle(fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                ],
              ),
              const Divider(height: 32),
              Text('Description',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(t.description),
              if (t.resolution != null && t.resolution!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Resolution',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF15803D))),
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
                subtitle: Text('${s.employeeNumber} â€¢ ${Fmt.role(s.role)}'),
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
      elevation: 0,
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
                    label: const Text('Assign toâ€¦'),
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
      elevation: 0,
      color: AppTheme.primary.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info_outline, color: AppTheme.primary),
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
/// Comments tab: comment box + timeline.
class _CommentsTab extends ConsumerStatefulWidget {
  const _CommentsTab({required this.detail, required this.user});
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
      showSnack(context, 'Please write a comment or pick a file first', error: true);
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
    }, _internal ? 'Internal note added' : 'Comment posted');
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.user.isStaff;
    final events = <(DateTime, Widget)>[
      for (final a in widget.detail.activities) (a.createdAt, _ActivityItem(a)),
      for (final c in widget.detail.comments) (c.createdAt, _CommentItem(c)),
    ]..sort((x, y) => y.$1.compareTo(x.$1)); // newest first

    // Chat layout: history scrolls on top, the comment input is pinned to the
    // bottom. Keeping the text field OUT of the scrollable stops Flutter's
    // ensure-visible logic from nudging the page down on every keystroke.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Add a comment', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
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
                                ? 'Reply to the employee, or add a technical note'
                                : 'Add details or reply to IT Support',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
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
                        tooltip: 'Lampiran',
                      ),
                      const SizedBox(width: 6),
                      FilledButton.icon(
                        key: const Key('post_comment_button'),
                        onPressed: busy ? null : _post,
                        icon: busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send),
                        label: Text(_internal ? 'Add note' : 'Post comment'),
                      ),
                    ],
                  ),
                  if (_pickedBytes != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file, size: 16, color: AppTheme.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _pickedFileName!,
                              style: const TextStyle(fontSize: 12, color: AppTheme.primary),
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
                            child: const Icon(Icons.close, size: 18, color: AppTheme.primary),
                          ),
                        ],
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
                child: Text('â€œ${a.note}â€', style: const TextStyle(fontStyle: FontStyle.italic)),
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
          color: c.isInternal ? const Color(0xFFFEF3C7) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: c.isInternal ? Border.all(color: const Color(0xFFFDE047)) : null,
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
                Text(Fmt.dateTime(c.createdAt), style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                if (c.isInternal)
                  Text('INTERNAL NOTE',
                      style: TextStyle(
                          color: const Color(0xFFB45309), fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 6),
            SelectionArea(child: Text(c.content)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
/// Attachments tab: lists files attached to the ticket with download links.
class _AttachmentsTab extends ConsumerStatefulWidget {
  const _AttachmentsTab({required this.ticket});
  final TicketModel ticket;

  @override
  ConsumerState<_AttachmentsTab> createState() => _AttachmentsTabState();
}

class _AttachmentsTabState extends ConsumerState<_AttachmentsTab> {
  @override
  Widget build(BuildContext context) {
    final attachments = ref.watch(attachmentsProvider(widget.ticket.id));

    return attachments.when(
      data: (list) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lampiran', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            if (list.isEmpty)
              const Center(child: Text('Belum ada lampiran.'))
            else
              ...[
                for (final a in list) _AttachmentItem(attachment: a),
              ],
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Gagal memuat lampiran: $e')),
    );
  }
}

class _AttachmentItem extends ConsumerWidget {
  const _AttachmentItem({required this.attachment});
  final AttachmentModel attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          attachment.isImage ? Icons.image : Icons.insert_drive_file,
          color: AppTheme.primary,
        ),
        title: Text(attachment.fileName),
        subtitle: Text(
          '${attachment.displaySize}  •  ${attachment.mimeType}  •  '
          'diunggah ${Fmt.dateTime(attachment.createdAt)}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.download),
          onPressed: () async {
            final url = await ref.read(attachmentActionsProvider).getDownloadUrl(attachment.id);
            if (url == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tidak dapat mengakses lampiran')),
              );
              return;
            }
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Unduh Lampiran'),
                content: Text('Tautan unduhan (berlaku 5 menit):\n$url'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tutup'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
/// Upload tab: pick a file and upload it as a ticket attachment.
class _UploadTab extends ConsumerStatefulWidget {
  const _UploadTab({required this.ticket, required this.user});
  final TicketModel ticket;
  final UserModel user;

  @override
  ConsumerState<_UploadTab> createState() => _UploadTabState();
}

class _UploadTabState extends ConsumerState<_UploadTab> {
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
      _setStatus('Gagal mengunggah: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Unggah Lampiran', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Text(
            'Pilih file untuk dilampiri pada tiket ini. '
            'Maks 10 MB per file. Tipe yang diizinkan: PDF, PNG, JPG, DOC, DOCX, XLS, XLSX, TXT, ZIP.',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _pickAndUpload,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload),
            label: Text(_busy ? 'Mengunggah…' : 'Pilih file…'),
          ),
          const SizedBox(height: 16),
          Text(
            'Catatan: Lampiran hanya dapat diakses oleh pengguna yang dapat melihat tiket ini '
            '(atas RLS basis data). File disimpan di Storage pribadi, tidak tersedia untuk publik.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusError ? Colors.red[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _statusError ? Colors.red[200]! : Colors.green[200]!,
                ),
              ),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  color: _statusError ? Colors.red[800] : Colors.green[800],
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
      'priority ${Fmt.priority(a.oldValue)} â†’ ${Fmt.priority(a.newValue)} by $who',
    ActivityModel.actionCategoryChanged =>
      'category ${a.oldValue} â†’ ${a.newValue} by $who',
    _ => 'status ${Fmt.status(a.oldValue)} â†’ ${Fmt.status(a.newValue)} by $who',
  };
}
/// A tab bar view that wraps its children with keyboard avoidance logic,
/// preventing the view from moving upward when typing in comment inputs.
/// When the user taps outside the focused field, the keyboard dismisses.
class _KeyboardAvoidingTabBarView extends ConsumerWidget {
  const _KeyboardAvoidingTabBarView({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: TabBarView(children: children),
    );
  }
}

