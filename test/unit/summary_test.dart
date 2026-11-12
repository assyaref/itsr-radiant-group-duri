import 'package:flutter_test/flutter_test.dart';
import 'package:itsr_radiant/models/ticket_model.dart';
import 'package:itsr_radiant/models/ticket_summary.dart';
import 'package:itsr_radiant/utils/summary_pdf.dart';

TicketModel t(String id, String status, String cat, String pri, {Duration? took}) {
  final created = DateTime.utc(2026, 11, 1, 8);
  return TicketModel(
    id: id, ticketNumber: 'ITSR-0000$id', subject: 'Masalah $id ✓ 😀', description: 'x',
    category: cat, priority: pri, status: status, reporterId: 'u', createdAt: created,
    updatedAt: created, resolvedAt: took == null ? null : created.add(took), reporterName: 'Andi',
  );
}

void main() {
  final tickets = [
    t('1', 'open', 'Hardware', 'high'),
    t('2', 'in_progress', 'Hardware', 'medium'),
    t('3', 'resolved', 'Software', 'low', took: const Duration(hours: 4)),
    t('4', 'closed', 'Network', 'high', took: const Duration(hours: 8)),
  ];

  test('summary groups statuses, categories, priorities and resolution time', () {
    final s = TicketSummary.of(tickets);
    expect(s.total, 4);
    expect([s.waiting, s.inProgress, s.done], [1, 1, 2]);
    expect(s.byCategory.keys.first, 'Hardware');
    expect(s.byCategory['Hardware'], 2);
    expect(s.byPriority['high'], 2);
    expect(s.averageResolution, const Duration(hours: 6));
    expect(TicketSummary.formatDuration(s.averageResolution), '6 jam 0 menit');
    expect(s.completionRate, 0.5);
  });

  test('empty summary is safe', () {
    final s = TicketSummary.of(const []);
    expect(s.total, 0);
    expect(s.completionRate, 0);
    expect(TicketSummary.formatDuration(s.averageResolution), '-');
  });

  test('PDF export builds a valid PDF, even with emoji in subjects', () async {
    final period = SummaryPeriod('30 hari', DateTime(2026, 10, 15), DateTime(2026, 11, 14));
    final bytes = await buildSummaryPdf(
      summary: TicketSummary.of(tickets),
      period: period,
      scopeLabel: 'Semua tiket',
      generatedBy: 'Budi Santoso',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });
}
