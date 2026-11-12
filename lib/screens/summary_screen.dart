import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/ticket_summary.dart';
import '../providers/auth_provider.dart';
import '../providers/tickets_provider.dart';
import '../utils/browser_files.dart';
import '../utils/error_messages.dart';
import '../utils/formatters.dart';
import '../utils/summary_pdf.dart';
import '../widgets/common.dart';
import '../widgets/employee_ui.dart';

/// "Ringkasan Tiket": totals, status, category and priority breakdown,
/// average resolution time and the ticket list for a period, exportable as
/// PDF. Employees see their own tickets; IT Support / admins see all.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  late final List<SummaryPeriod> _presets = SummaryPeriod.presets(
    DateTime.now(),
  );
  late SummaryPeriod _period = _presets[1]; // 30 hari
  bool _exporting = false;

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _period.from,
        end: _period.to.subtract(const Duration(days: 1)),
      ),
      helpText: 'Pilih periode',
      saveText: 'Terapkan',
    );
    if (range == null) return;
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
    ).add(const Duration(days: 1));
    setState(() => _period = SummaryPeriod('Kustom', start, end));
  }

  Future<void> _export(TicketSummary summary) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await buildSummaryPdf(
        summary: summary,
        period: _period,
        scopeLabel: user.isStaff
            ? 'Semua tiket'
            : 'Tiket milik ${user.fullName}',
        generatedBy: user.fullName,
      );
      String d(DateTime x) =>
          '${x.year}${x.month.toString().padLeft(2, '0')}${x.day.toString().padLeft(2, '0')}';
      final last = _period.to.subtract(const Duration(days: 1));
      await downloadBytes(
        bytes,
        'ringkasan-tiket-${d(_period.from)}-${d(last)}.pdf',
        'application/pdf',
      );
      if (mounted) showSnack(context, 'PDF diunduh');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final async = ref.watch(ticketSummaryProvider(_period));
    final summary = async.valueOrNull;

    return Scaffold(
      backgroundColor: EColors.page,
      appBar: EHeader(
        title: 'Ringkasan Tiket',
        onBack: () => goBack(context),
        trailing: IconButton(
          key: const Key('export_pdf_button'),
          tooltip: 'Export PDF',
          onPressed: summary == null || _exporting
              ? null
              : () => _export(summary),
          icon: _exporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf_outlined, color: EColors.red),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in _presets) ...[
                  ESegment(
                    label: p.label,
                    selected: _period == p,
                    onTap: () => setState(() => _period = p),
                  ),
                  const SizedBox(width: 8),
                ],
                ESegment(
                  key: const Key('custom_period'),
                  label: _period.label == 'Kustom' ? 'Kustom ✓' : 'Kustom…',
                  selected: _period.label == 'Kustom',
                  onTap: _pickCustom,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${Fmt.date(_period.from)} – ${Fmt.date(_period.to.subtract(const Duration(days: 1)))}'
            ' · ${(user?.isStaff ?? false) ? 'semua tiket' : 'tiket Anda'}',
            style: const TextStyle(color: EColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          async.when(
            skipLoadingOnRefresh: true,
            loading: () => const SizedBox(height: 240, child: LoadingView()),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(ticketSummaryProvider(_period)),
            ),
            data: (s) => _SummaryBody(
              summary: s,
              exporting: _exporting,
              onExport: () => _export(s),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({
    required this.summary,
    required this.exporting,
    required this.onExport,
  });
  final TicketSummary summary;
  final bool exporting;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final stats = [
      (
        'Total Tiket',
        '${s.total}',
        Icons.confirmation_number_rounded,
        EColors.blue,
      ),
      ('Menunggu', '${s.waiting}', Icons.hourglass_top_rounded, EColors.purple),
      ('Diproses', '${s.inProgress}', Icons.autorenew_rounded, EColors.amber),
      ('Selesai', '${s.done}', Icons.check_rounded, EColors.green),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 80,
          ),
          children: [
            for (final (label, value, icon, color) in stats)
              ECard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.15),
                      ),
                      child: Icon(icon, size: 18, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: EColors.ink,
                            ),
                          ),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: EColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ECard(
          child: Row(
            children: [
              const Icon(Icons.timer_outlined, color: EColors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rata-rata waktu penyelesaian',
                      style: TextStyle(fontSize: 12, color: EColors.muted),
                    ),
                    Text(
                      TicketSummary.formatDuration(s.averageResolution),
                      key: const Key('avg_resolution'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: EColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Tingkat selesai',
                    style: TextStyle(fontSize: 12, color: EColors.muted),
                  ),
                  Text(
                    '${(s.completionRate * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: EColors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Breakdown(
          title: 'Per Kategori',
          total: s.total,
          rows: [
            for (final e in s.byCategory.entries)
              (
                e.key,
                e.value,
                categoryStyle(e.key).$2,
                categoryStyle(e.key).$1,
              ),
          ],
        ),
        const SizedBox(height: 12),
        _Breakdown(
          title: 'Per Prioritas',
          total: s.total,
          rows: [
            for (final e in s.byPriority.entries)
              (
                Fmt.priority(e.key),
                e.value,
                EColors.priority(e.key),
                Icons.error_rounded,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Daftar Tiket (${s.total})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: EColors.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (s.tickets.isEmpty)
          const ECard(
            child: Text(
              'Tidak ada tiket pada periode ini.',
              textAlign: TextAlign.center,
              style: TextStyle(color: EColors.muted),
            ),
          )
        else
          for (final t in s.tickets.take(50)) ...[
            TicketRow(t),
            const SizedBox(height: 8),
          ],
        if (s.tickets.length > 50)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '+${s.tickets.length - 50} tiket lainnya tercantum di PDF.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: EColors.muted, fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 8),
        EPrimaryButton(
          key: const Key('export_pdf_bottom'),
          label: 'Export PDF',
          icon: Icons.picture_as_pdf_outlined,
          busy: exporting,
          onPressed: onExport,
        ),
      ],
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.title,
    required this.total,
    required this.rows,
  });
  final String title;
  final int total;
  final List<(String, int, Color, IconData)> rows;

  @override
  Widget build(BuildContext context) => ECard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: EColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty || total == 0)
          const Text('Belum ada data.', style: TextStyle(color: EColors.muted)),
        if (total > 0)
          for (final (label, count, color, icon) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: EColors.text),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: count / total,
                        minHeight: 8,
                        color: color,
                        backgroundColor: const Color(0xFFF1F5F9),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$count',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: EColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    ),
  );
}

/// Small entry card used on the Beranda / Profil.
class SummaryEntryTile extends StatelessWidget {
  const SummaryEntryTile({super.key});

  @override
  Widget build(BuildContext context) => ECard(
    padding: EdgeInsets.zero,
    child: ListTile(
      key: const Key('open_summary'),
      leading: const Icon(
        Icons.insert_chart_outlined_rounded,
        color: EColors.blue,
      ),
      title: const Text(
        'Ringkasan Tiket',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: const Text('Statistik & export PDF'),
      trailing: const Icon(Icons.chevron_right, color: EColors.grey),
      onTap: () => context.push('/summary'),
    ),
  );
}
