import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/ticket_summary.dart';
import 'formatters.dart';

/// Builds the "Ringkasan Tiket" PDF report.
///
/// The built-in PDF fonts only cover Latin-1, so user text is sanitised
/// (characters outside Latin-1 become '?') instead of breaking the export.
Future<Uint8List> buildSummaryPdf({
  required TicketSummary summary,
  required SummaryPeriod period,
  required String scopeLabel,
  required String generatedBy,
  DateTime? generatedAt,
}) async {
  final now = generatedAt ?? DateTime.now();
  final doc = pw.Document(
    title: 'Ringkasan Tiket IT Support',
    author: _latin1(generatedBy),
  );
  const blue = PdfColor.fromInt(0xFF2563EB);
  const grey = PdfColor.fromInt(0xFF64748B);
  final periodText =
      '${Fmt.date(period.from)} s/d ${Fmt.date(period.to.subtract(const Duration(days: 1)))}';

  pw.Widget statBox(String label, String value) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.only(right: 6),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: grey)),
        ],
      ),
    ),
  );

  pw.Widget countTable(
    String title,
    Map<String, int> data,
    String Function(String) name,
  ) => pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: ['', 'Jumlah', '%'],
          data: [
            for (final e in data.entries)
              [
                _latin1(name(e.key)),
                '${e.value}',
                summary.total == 0
                    ? '0%'
                    : '${(e.value * 100 / summary.total).round()}%',
              ],
          ],
          headerStyle: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
          },
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        ),
      ],
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Text(
              'Ringkasan Tiket - $periodText',
              style: const pw.TextStyle(fontSize: 8, color: grey),
            ),
      footer: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'ITSR Radiant Group Duri - IT Support Cabang Duri',
            style: const pw.TextStyle(fontSize: 8, color: grey),
          ),
          pw.Text(
            'Halaman ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: grey),
          ),
        ],
      ),
      build: (ctx) => [
        pw.Text(
          'Ringkasan Tiket IT Support',
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: blue,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Periode: $periodText (${_latin1(period.label)})',
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.Text(
          'Cakupan: ${_latin1(scopeLabel)}',
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.Text(
          'Dibuat oleh ${_latin1(generatedBy)} pada ${Fmt.dateTime(now)}',
          style: const pw.TextStyle(fontSize: 9, color: grey),
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          children: [
            statBox('Total tiket', '${summary.total}'),
            statBox('Menunggu', '${summary.waiting}'),
            statBox('Diproses', '${summary.inProgress}'),
            statBox('Selesai', '${summary.done}'),
            statBox(
              'Rata-rata penyelesaian',
              _latin1(TicketSummary.formatDuration(summary.averageResolution)),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Tingkat penyelesaian: ${(summary.completionRate * 100).round()}%',
          style: const pw.TextStyle(fontSize: 9, color: grey),
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            countTable('Per kategori', summary.byCategory, (k) => k),
            pw.SizedBox(width: 16),
            countTable('Per prioritas', summary.byPriority, Fmt.priority),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Daftar tiket (${summary.total})',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        if (summary.tickets.isEmpty)
          pw.Text(
            'Tidak ada tiket pada periode ini.',
            style: const pw.TextStyle(fontSize: 9),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: [
              'No. Tiket',
              'Judul',
              'Kategori',
              'Prioritas',
              'Status',
              'Pelapor',
              'Dibuat',
              'Selesai',
            ],
            data: [
              for (final t in summary.tickets)
                [
                  t.ticketNumber,
                  _latin1(t.subject),
                  _latin1(t.category),
                  Fmt.priority(t.priority),
                  Fmt.statusId(t.status),
                  _latin1(t.reporterName ?? '-'),
                  Fmt.date(t.createdAt),
                  (t.resolvedAt ?? t.closedAt) == null
                      ? '-'
                      : Fmt.date((t.resolvedAt ?? t.closedAt)!),
                ],
            ],
            headerStyle: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: blue),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 3,
              vertical: 3,
            ),
            columnWidths: {
              0: const pw.FixedColumnWidth(58),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(1.3),
              3: const pw.FixedColumnWidth(42),
              4: const pw.FixedColumnWidth(52),
              5: const pw.FlexColumnWidth(1.4),
              6: const pw.FixedColumnWidth(50),
              7: const pw.FixedColumnWidth(50),
            },
            oddRowDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF8FAFC),
            ),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
      ],
    ),
  );
  return doc.save();
}

/// Keeps Latin-1 characters; replaces anything else (emoji, CJK, ...) with '?'.
String _latin1(String s) => String.fromCharCodes(
  s.runes.map(
    (r) => switch (r) {
      0x2013 || 0x2014 => 0x2D, // – — -> -
      0x2018 || 0x2019 => 0x27,
      0x201C || 0x201D => 0x22,
      0x2026 => 0x2E,
      < 0x100 => r,
      _ => 0x3F,
    },
  ),
);
