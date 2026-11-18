import 'package:intl/intl.dart';

class Fmt {
  Fmt._();

  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, HH:mm');

  static String date(DateTime d) => _date.format(d.toLocal());
  static String dateTime(DateTime d) => _dateTime.format(d.toLocal());
  static String time(DateTime d) => _time.format(d.toLocal());
  static final DateFormat _time = DateFormat('HH:mm');

  static String relative(DateTime d, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(d.toLocal());
    if (diff.inMinutes < 1) return 'baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays < 7) return '${diff.inDays} hari lalu';
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
    'superadmin': 'Super Admin',
  };

  static String status(String? s) => _status[s] ?? (s ?? 'Unknown');

  /// Indonesian status labels for the employee-facing design.
  static String statusId(String? s) => switch (s) {
        'open' => 'Menunggu',
        'assigned' => 'Ditugaskan',
        'in_progress' => 'Diproses',
        'pending_user' => 'Menunggu Anda',
        'resolved' => 'Selesai',
        'closed' => 'Ditutup',
        'reopened' => 'Dibuka Ulang',
        _ => status(s),
      };

  static String role(String? r) => _role[r] ?? (r ?? 'Unknown');
  static String priority(String? p) =>
      (p == null || p.isEmpty) ? 'Unknown' : p[0].toUpperCase() + p.substring(1);
}
