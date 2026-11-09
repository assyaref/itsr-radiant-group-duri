import 'package:flutter_test/flutter_test.dart';
import 'package:itsr_radiant/models/activity_model.dart';
import 'package:itsr_radiant/models/comment_model.dart';
import 'package:itsr_radiant/models/ticket_model.dart';
import 'package:itsr_radiant/models/ticket_stats.dart';
import 'package:itsr_radiant/models/user_model.dart';

/// Payloads shaped exactly like PostgREST responses for the queries in
/// SupabaseTicketRepository (snake_case + embedded resources). The previous
/// models expected camelCase keys and failed on every real row.
void main() {
  test('TicketModel parses snake_case row with embedded reporter/assignee', () {
    final t = TicketModel.fromJson({
      'id': 'a1',
      'ticket_number': 'ITSR-00001',
      'subject': 'Laptop will not boot',
      'description': 'Black screen',
      'category': 'Hardware',
      'subcategory': null,
      'priority': 'high',
      'status': 'assigned',
      'reporter_id': 'u1',
      'assigned_to_id': 'u2',
      'resolution': null,
      'created_at': '2026-11-08T01:02:03.123456+00:00',
      'updated_at': '2026-11-08T01:02:03+00:00',
      'resolved_at': null,
      'closed_at': null,
      'reporter': {'full_name': 'Employee A'},
      'assignee': {'full_name': 'IT One'},
    });
    expect(t.ticketNumber, 'ITSR-00001');
    expect(t.reporterName, 'Employee A');
    expect(t.assigneeName, 'IT One');
    expect(t.isFinished, isFalse);
  });

  test('TicketModel tolerates null embedded assignee', () {
    final t = TicketModel.fromJson({
      'id': 'a1', 'ticket_number': 'ITSR-00002', 'subject': 's', 'description': 'd',
      'category': 'Network', 'priority': 'low', 'status': 'resolved', 'reporter_id': 'u1',
      'created_at': '2026-11-08T00:00:00Z', 'updated_at': '2026-11-08T00:00:00Z',
      'reporter': {'full_name': 'Employee A'}, 'assignee': null,
    });
    expect(t.assigneeName, isNull);
    expect(t.isFinished, isTrue);
  });

  test('UserModel parses profile row and derives role flags', () {
    final u = UserModel.fromJson({
      'id': 'u1', 'employee_number': 'IT001', 'email': 'it@example.test', 'full_name': 'IT One',
      'department': 'IT', 'role': 'it_support', 'phone_number': null, 'is_active': true,
      'created_at': '2026-11-08T00:00:00Z', 'updated_at': '2026-11-08T00:00:00Z',
    });
    expect(u.isStaff, isTrue);
    expect(u.isAdmin, isFalse);
  });

  test('CommentModel and ActivityModel parse embedded names', () {
    final c = CommentModel.fromJson({
      'id': 'c1', 'ticket_id': 'a1', 'author_id': 'u1', 'content': 'hi', 'is_internal': true,
      'created_at': '2026-11-08T00:00:00Z', 'author': {'full_name': 'IT One'},
    });
    expect(c.authorName, 'IT One');
    expect(c.isInternal, isTrue);

    final a = ActivityModel.fromJson({
      'id': 'x', 'ticket_id': 'a1', 'actor_id': null, 'action': 'status_changed',
      'old_value': 'open', 'new_value': 'in_progress', 'note': null,
      'created_at': '2026-11-08T00:00:00Z', 'actor': null,
      'ticket': {'ticket_number': 'ITSR-00001', 'subject': 'Laptop'},
    });
    expect(a.actorId, isNull, reason: 'system actions have no actor');
    expect(a.ticketNumber, 'ITSR-00001');
    expect(a.ticketSubject, 'Laptop');
  });

  test('TicketStats parses bigint counts (PostgREST may send numbers)', () {
    final s = TicketStats.fromJson({
      'total': 7, 'open': 3, 'in_progress': 2, 'resolved': 1, 'closed': 1, 'unassigned': '2',
    });
    expect(s.total, 7);
    expect(s.inProgress, 2);
    expect(s.unassigned, 2);
  });
}
