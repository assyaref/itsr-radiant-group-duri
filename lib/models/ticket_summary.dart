import 'ticket_model.dart';

/// Reporting period for the ticket summary.
class SummaryPeriod {
  const SummaryPeriod(this.label, this.from, this.to);
  final String label;
  final DateTime from; // inclusive
  final DateTime to; // exclusive

  @override
  bool operator ==(Object other) =>
      other is SummaryPeriod &&
      other.from == from &&
      other.to == to &&
      other.label == label;

  @override
  int get hashCode => Object.hash(label, from, to);

  static List<SummaryPeriod> presets(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return [
      SummaryPeriod(
        '7 hari',
        today.subtract(const Duration(days: 6)),
        tomorrow,
      ),
      SummaryPeriod(
        '30 hari',
        today.subtract(const Duration(days: 29)),
        tomorrow,
      ),
      SummaryPeriod('Bulan ini', DateTime(now.year, now.month), tomorrow),
      SummaryPeriod('3 bulan', DateTime(now.year, now.month - 2), tomorrow),
      SummaryPeriod('Tahun ini', DateTime(now.year), tomorrow),
    ];
  }
}

/// Aggregates computed from the tickets created in a period.
class TicketSummary {
  TicketSummary._({
    required this.tickets,
    required this.waiting,
    required this.inProgress,
    required this.done,
    required this.byCategory,
    required this.byPriority,
    required this.averageResolution,
    required this.resolvedCount,
  });

  final List<TicketModel> tickets;
  final int waiting;
  final int inProgress;
  final int done;
  final Map<String, int> byCategory; // sorted, largest first
  final Map<String, int> byPriority; // critical, high, medium, low
  final Duration? averageResolution;
  final int resolvedCount;

  int get total => tickets.length;
  double get completionRate => total == 0 ? 0 : done / total;

  static const _waiting = {'open', 'assigned', 'reopened'};
  static const _inProgress = {'in_progress', 'pending_user'};
  static const _done = {'resolved', 'closed'};

  factory TicketSummary.of(List<TicketModel> tickets) {
    final cats = <String, int>{};
    final pris = <String, int>{'critical': 0, 'high': 0, 'medium': 0, 'low': 0};
    var resolvedMinutes = 0, resolved = 0;
    for (final t in tickets) {
      cats[t.category] = (cats[t.category] ?? 0) + 1;
      pris[t.priority] = (pris[t.priority] ?? 0) + 1;
      final end = t.resolvedAt ?? t.closedAt;
      if (end != null && end.isAfter(t.createdAt)) {
        resolvedMinutes += end.difference(t.createdAt).inMinutes;
        resolved++;
      }
    }
    final sortedCats = Map.fromEntries(
      cats.entries.toList()..sort(
        (a, b) =>
            b.value != a.value ? b.value - a.value : a.key.compareTo(b.key),
      ),
    );
    return TicketSummary._(
      tickets: tickets,
      waiting: tickets.where((t) => _waiting.contains(t.status)).length,
      inProgress: tickets.where((t) => _inProgress.contains(t.status)).length,
      done: tickets.where((t) => _done.contains(t.status)).length,
      byCategory: sortedCats,
      byPriority: pris,
      averageResolution: resolved == 0
          ? null
          : Duration(minutes: resolvedMinutes ~/ resolved),
      resolvedCount: resolved,
    );
  }

  /// "2 hari 4 jam", "5 jam 10 menit", "-" (Indonesian).
  static String formatDuration(Duration? d) {
    if (d == null) return '-';
    if (d.inDays >= 1) return '${d.inDays} hari ${d.inHours % 24} jam';
    if (d.inHours >= 1) return '${d.inHours} jam ${d.inMinutes % 60} menit';
    return '${d.inMinutes} menit';
  }
}
