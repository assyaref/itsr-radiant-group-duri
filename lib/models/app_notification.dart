import 'activity_model.dart';
import '../utils/formatters.dart';

/// An in-app notification derived from the ticket activity log or a comment.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.time,
    this.ticketId,
  });

  /// 'created' | 'updated' | 'comment' | 'resolved' | 'closed' | 'reopened' | 'system'
  final String kind;
  final String id;
  final String title;
  final String body;
  final DateTime time;
  final String? ticketId;

  /// "Tiket" tab = everything about tickets; "Sistem" = automatic events.
  bool get isSystem => kind == 'system';

  factory AppNotification.fromActivity(ActivityModel a) {
    final no = a.ticketNumber ?? 'Tiket';
    final (kind, title, body) = switch (a.action) {
      ActivityModel.actionCreated => (
        'created',
        'Tiket baru',
        'Tiket $no telah dibuat.',
      ),
      ActivityModel.actionAssigned =>
        a.newValue == null
            ? (
                'updated',
                'Tiket diperbarui',
                'Tiket $no dikembalikan ke antrean IT Support.',
              )
            : (
                'updated',
                'Tiket ditangani',
                'Tiket $no sedang ditangani ${a.actorName ?? 'IT Support'}.',
              ),
      ActivityModel.actionResolved => (
        'resolved',
        'Tiket selesai',
        'Tiket $no telah selesai.',
      ),
      ActivityModel.actionClosed => (
        'closed',
        'Tiket ditutup',
        'Tiket $no telah ditutup.',
      ),
      ActivityModel.actionReopened => (
        'reopened',
        'Tiket dibuka ulang',
        'Tiket $no dibuka kembali.',
      ),
      ActivityModel.actionPriorityChanged => (
        'updated',
        'Prioritas diubah',
        'Prioritas tiket $no diubah menjadi ${Fmt.priority(a.newValue)}.',
      ),
      ActivityModel.actionCategoryChanged => (
        'updated',
        'Kategori diubah',
        'Kategori tiket $no diubah menjadi ${a.newValue ?? '-'}.',
      ),
      _ => (
        'updated',
        'Tiket diperbarui',
        'Tiket $no status diubah menjadi ${Fmt.status(a.newValue)}.',
      ),
    };
    return AppNotification(
      id: 'a-${a.id}',
      kind: a.actorId == null && kind == 'updated' ? 'system' : kind,
      title: title,
      body: body,
      time: a.createdAt,
      ticketId: a.ticketId,
    );
  }

  factory AppNotification.fromCommentRow(Map<String, dynamic> row) {
    final author = row['author'] is Map
        ? row['author']['full_name'] as String?
        : null;
    final no = row['ticket'] is Map
        ? row['ticket']['ticket_number'] as String?
        : null;
    return AppNotification(
      id: 'c-${row['id']}',
      kind: 'comment',
      title: 'Komentar baru',
      body:
          '${author ?? 'IT Support'} memberikan komentar pada tiket ${no ?? ''}.'
              .replaceAll(' .', '.'),
      time: DateTime.parse(row['created_at'] as String),
      ticketId: row['ticket_id'] as String?,
    );
  }
}
