import 'package:intl/intl.dart';

class Fmt {
  Fmt._();

  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, HH:mm');

  /// "Jan", "Feb", ... for chart axes.
  static String monthShort(DateTime d) => DateFormat('MMM').format(d.toLocal());

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
    'employee': 'Karyawan',
    'it_support': 'IT Support',
    'administrator': 'Administrator',
  };

  /// Indonesian labels used by the employee screens (design wording).
  static const Map<String, String> _statusId = {
    'open': 'Menunggu',
    'assigned': 'Ditugaskan',
    'in_progress': 'Diproses',
    'pending_user': 'Butuh Respons',
    'resolved': 'Selesai',
    'closed': 'Ditutup',
    'reopened': 'Dibuka Ulang',
  };

  static String statusId(String? s) => _statusId[s] ?? (s ?? '-');

  /// "5 menit lalu", "2 jam lalu", "3 hari lalu", else a date.
  static String relativeId(DateTime d, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(d.toLocal());
    if (diff.inMinutes < 1) return 'baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays < 7) return '${diff.inDays} hari lalu';
    return date(d);
  }

  static String status(String? s) => _status[s] ?? (s ?? 'Unknown');
  static String role(String? r) => _role[r] ?? (r ?? 'Unknown');
  static String priority(String? p) => (p == null || p.isEmpty)
      ? 'Unknown'
      : p[0].toUpperCase() + p.substring(1);
}
