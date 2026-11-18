import 'activity_model.dart';
import 'comment_model.dart';
import 'ticket_model.dart';

/// Result of the `ticket_stats` RPC (counts are RLS-scoped server-side).
class TicketStats {
  final int total;
  final int open;
  final int inProgress;
  final int resolved;
  final int closed;
  final int unassigned;

  const TicketStats({
    this.total = 0,
    this.open = 0,
    this.inProgress = 0,
    this.resolved = 0,
    this.closed = 0,
    this.unassigned = 0,
  });

  static int _n(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  factory TicketStats.fromJson(Map<String, dynamic> j) => TicketStats(
    total: _n(j['total']),
    open: _n(j['open']),
    inProgress: _n(j['in_progress']),
    resolved: _n(j['resolved']),
    closed: _n(j['closed']),
    unassigned: _n(j['unassigned']),
  );
}

/// Everything the ticket detail screen shows, loaded under the caller's RLS.
class TicketDetail {
  final TicketModel ticket;
  final List<CommentModel> comments;
  final List<ActivityModel> activities;

  const TicketDetail({
    required this.ticket,
    required this.comments,
    required this.activities,
  });
}

/// A staff member that a ticket can be assigned to.
class StaffMember {
  final String id;
  final String fullName;
  final String employeeNumber;
  final String role;

  const StaffMember({
    required this.id,
    required this.fullName,
    required this.employeeNumber,
    required this.role,
  });

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
    id: j['id'] as String,
    fullName: j['full_name'] as String,
    employeeNumber: j['employee_number'] as String,
    role: j['role'] as String,
  );
}
