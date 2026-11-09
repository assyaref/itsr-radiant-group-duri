import 'package:intl/intl.dart';

class Fmt {
  Fmt._();

  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, HH:mm');

  static String date(DateTime d) => _date.format(d.toLocal());
  static String dateTime(DateTime d) => _dateTime.format(d.toLocal());

  static String relative(DateTime d, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(d.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return date(d);
  }

  static const Map<String, String> _status = {
    'open': 'Open',
    'assigned': 'Assigned',
    'in_progress': 'In Progress',
    'pending_user': 'Waiting for User',
    'resolved': 'Resolved',
    'closed': 'Closed',
    'reopened': 'Reopened',
  };

  static const Map<String, String> _role = {
    'employee': 'Employee',
    'it_support': 'IT Support',
    'administrator': 'Administrator',
  };

  static String status(String? s) => _status[s] ?? (s ?? 'Unknown');
  static String role(String? r) => _role[r] ?? (r ?? 'Unknown');
  static String priority(String? p) =>
      (p == null || p.isEmpty) ? 'Unknown' : p[0].toUpperCase() + p.substring(1);
}
