import 'ticket_model.dart';
import 'ticket_summary.dart';

/// One day on the "Tren Tiket" chart.
class TrendPoint {
  const TrendPoint(this.day, this.created, this.resolved);
  final DateTime day;
  final int created;
  final int resolved;
}

/// Everything the administrator / IT Support dashboard shows for a period.
class StaffDashboard {
  StaffDashboard({
    required this.period,
    required this.current,
    required this.previous,
    required this.latest,
  }) : trend = buildTrend(period, current.tickets);

  final SummaryPeriod period;
  final TicketSummary current;

  /// The equally long period right before [period], for the % change.
  final TicketSummary previous;

  /// Newest tickets overall (right-hand "Tiket Terbaru" panel).
  final List<TicketModel> latest;

  final List<TrendPoint> trend;

  /// Change in % versus the previous period; null when there is no base.
  static double? change(int now, int before) =>
      before == 0 ? null : (now - before) * 100 / before;

  static SummaryPeriod previousOf(SummaryPeriod p) {
    final length = p.to.difference(p.from);
    return SummaryPeriod('Sebelumnya', p.from.subtract(length), p.from);
  }

  /// Tickets created per local day, and tickets resolved/closed per local day
  /// (of those created in the period).
  static List<TrendPoint> buildTrend(SummaryPeriod p, List<TicketModel> tickets) {
    DateTime dayOf(DateTime d) {
      final l = d.toLocal();
      return DateTime(l.year, l.month, l.day);
    }

    final created = <DateTime, int>{};
    final resolved = <DateTime, int>{};
    for (final t in tickets) {
      final c = dayOf(t.createdAt);
      created[c] = (created[c] ?? 0) + 1;
      final end = t.resolvedAt ?? t.closedAt;
      if (end != null) {
        final r = dayOf(end);
        resolved[r] = (resolved[r] ?? 0) + 1;
      }
    }
    final out = <TrendPoint>[];
    for (var d = DateTime(p.from.year, p.from.month, p.from.day);
        d.isBefore(p.to) && out.length < 400;
        d = DateTime(d.year, d.month, d.day + 1)) {
      out.add(TrendPoint(d, created[d] ?? 0, resolved[d] ?? 0));
    }
    return out;
  }
}
