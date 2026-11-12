import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/staff_dashboard.dart';
import '../../models/ticket_summary.dart';
import '../../models/user_model.dart';
import '../../providers/tickets_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';
import '../../widgets/employee_ui.dart';

/// Colours for categories in charts (stable by position).
const chartPalette = [
  Color(0xFF2563EB),
  Color(0xFFEF4444),
  Color(0xFF38BDF8),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFF8B5CF6),
  Color(0xFF94A3B8),
];

/// Period picker shared by the dashboard and the report.
class PeriodButton extends StatelessWidget {
  const PeriodButton({super.key, required this.period, required this.presets, required this.onChanged});
  final SummaryPeriod period;
  final List<SummaryPeriod> presets;
  final ValueChanged<SummaryPeriod> onChanged;

  Future<void> _custom(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: period.from, end: period.to.subtract(const Duration(days: 1))),
      helpText: 'Pilih periode',
      saveText: 'Terapkan',
    );
    if (range == null) return;
    onChanged(SummaryPeriod(
      'Kustom',
      DateTime(range.start.year, range.start.month, range.start.day),
      DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final label = '${Fmt.date(period.from)} - ${Fmt.date(period.to.subtract(const Duration(days: 1)))}';
    return PopupMenuButton<int>(
      key: const Key('period_button'),
      tooltip: 'Pilih periode',
      onSelected: (i) => i < 0 ? _custom(context) : onChanged(presets[i]),
      itemBuilder: (_) => [
        for (var i = 0; i < presets.length; i++)
          CheckedPopupMenuItem(value: i, checked: presets[i] == period, child: Text(presets[i].label)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: -1, child: Text('Pilih tanggal…')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: EColors.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_today_outlined, size: 16, color: EColors.muted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: EColors.text)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 18, color: EColors.muted),
        ]),
      ),
    );
  }
}

/// "1. Dashboard Administrator" (desktop) / "8. Tampilan Mobile (Administrator)".
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key, required this.user});
  final UserModel user;

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  late final List<SummaryPeriod> _presets = SummaryPeriod.presets(DateTime.now());
  late SummaryPeriod _period = _presets[2]; // Bulan ini

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(staffDashboardProvider(_period));
    final wide = MediaQuery.sizeOf(context).width >= 1200;
    final desktop = isDesktop(context);

    final header = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(
            desktop ? 'Selamat Datang, ${widget.user.fullName}' : 'Halo, ${widget.user.fullName}',
            style: TextStyle(fontSize: desktop ? 22 : 19, fontWeight: FontWeight.w800, color: EColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            desktop ? 'Kelola dan pantau seluruh tiket IT Support' : Fmt.role(widget.user.role),
            style: const TextStyle(color: EColors.muted, fontSize: 13),
          ),
        ]),
        PeriodButton(period: _period, presets: _presets, onChanged: (p) => setState(() => _period = p)),
      ],
    );

    final body = async.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox(height: 300, child: LoadingView()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(staffDashboardProvider(_period))),
      data: (d) {
        final kpis = _Kpis(d: d);
        final trend = _TrendCard(d: d);
        final donut = _CategoryCard(summary: d.current);
        final latest = _LatestCard(d: d);
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(children: [
                kpis,
                const SizedBox(height: 16),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: trend),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: donut),
                ]),
              ]),
            ),
            const SizedBox(width: 16),
            SizedBox(width: 320, child: latest),
          ]);
        }
        return Column(children: [
          kpis,
          const SizedBox(height: 16),
          trend,
          const SizedBox(height: 16),
          donut,
          const SizedBox(height: 16),
          latest,
        ]);
      },
    );

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(staffDashboardProvider(_period)),
      child: ListView(
        padding: EdgeInsets.all(desktop ? 24 : 16),
        children: [
          if (!desktop) const SizedBox(height: 8),
          header,
          const SizedBox(height: 20),
          body,
        ],
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.d});
  final StaffDashboard d;

  @override
  Widget build(BuildContext context) {
    final c = d.current, p = d.previous;
    final cards = [
      ('Total Tiket', c.total, p.total, Icons.confirmation_number_rounded, EColors.blue, true),
      ('Tiket Terbuka', c.waiting, p.waiting, Icons.inbox_rounded, EColors.red, false),
      ('Sedang Dikerjakan', c.inProgress, p.inProgress, Icons.engineering_rounded, EColors.blue, false),
      ('Tiket Selesai', c.done, p.done, Icons.verified_rounded, EColors.green, true),
    ];
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 760 ? 4 : 2;
      return GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: cols == 4 ? 104 : 96,
        ),
        children: [
          for (final (label, now, before, icon, color, upIsGood) in cards)
            _KpiCard(
              label: label,
              value: now,
              change: StaffDashboard.change(now, before),
              icon: icon,
              color: color,
              upIsGood: upIsGood,
            ),
        ],
      );
    });
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.change,
    required this.icon,
    required this.color,
    required this.upIsGood,
  });
  final String label;
  final int value;
  final double? change;
  final IconData icon;
  final Color color;
  final bool upIsGood;

  @override
  Widget build(BuildContext context) {
    final ch = change;
    final up = (ch ?? 0) >= 0;
    final good = ch == null || ch == 0 ? null : (up == upIsGood);
    final chColor = good == null ? EColors.muted : (good ? EColors.green : EColors.red);
    return ECard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: EColors.muted)),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$value', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: EColors.ink)),
              const Spacer(),
              if (ch != null)
                Flexible(
                  child: Text(
                    '${up ? '↑' : '↓'} ${ch.abs().round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: chColor),
                  ),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.d});
  final StaffDashboard d;

  @override
  Widget build(BuildContext context) {
    final pts = d.trend;
    final maxY = pts.fold<int>(0, (m, p) => [m, p.created, p.resolved].reduce((a, b) => a > b ? a : b));
    final top = (maxY < 4 ? 4 : maxY + (maxY / 4).ceil()).toDouble();
    final step = (pts.length / 6).ceil().clamp(1, 1000);
    LineChartBarData line(List<FlSpot> spots, Color color) => LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 2.2,
          dotData: FlDotData(show: pts.length <= 31, getDotPainter: (_, _, _, _) =>
              FlDotCirclePainter(radius: 2.4, color: Colors.white, strokeWidth: 1.6, strokeColor: color)),
          belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.10)),
        );
    return ECard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Tren Tiket', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: EColors.ink)),
              Text('Jumlah tiket masuk dan selesai per hari',
                  style: TextStyle(fontSize: 12, color: EColors.muted)),
            ]),
            Wrap(spacing: 12, runSpacing: 4, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                _legendDot(EColors.blue),
                const Text(' Tiket Masuk', style: TextStyle(fontSize: 12, color: EColors.text)),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _legendDot(EColors.green),
                const Text(' Tiket Selesai', style: TextStyle(fontSize: 12, color: EColors.text)),
              ]),
            ]),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: pts.isEmpty
              ? const Center(child: Text('Belum ada data.', style: TextStyle(color: EColors.muted)))
              : LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: top,
                    minX: 0,
                    maxX: (pts.length - 1).toDouble().clamp(1, 1000),
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFEFF2F7), strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (v, meta) => v == v.roundToDouble()
                              ? Text('${v.toInt()}', style: const TextStyle(fontSize: 11, color: EColors.muted))
                              : const SizedBox.shrink(),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          interval: 1,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            final last = pts.length - 1;
                            final showLast = i == last && (last % step == 0 || last % step >= step / 2);
                            if (i < 0 || i >= pts.length || (i % step != 0 && !showLast)) {
                              return const SizedBox.shrink();
                            }
                            final day = pts[i].day;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('${day.day} ${Fmt.monthShort(day)}',
                                  style: const TextStyle(fontSize: 10.5, color: EColors.muted)),
                            );
                          },
                        ),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => EColors.ink,
                        getTooltipItems: (spots) => [
                          for (final s in spots)
                            LineTooltipItem(
                              '${s.barIndex == 0 ? 'Masuk' : 'Selesai'}: ${s.y.toInt()}',
                              const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    lineBarsData: [
                      line([for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), pts[i].created.toDouble())],
                          EColors.blue),
                      line([for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), pts[i].resolved.toDouble())],
                          EColors.green),
                    ],
                  ),
                ),
        ),
      ]),
    );
  }
}

Widget _legendDot(Color c) =>
    Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.summary});
  final TicketSummary summary;

  @override
  Widget build(BuildContext context) {
    final entries = summary.byCategory.entries.toList();
    return ECard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Tiket per Kategori', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: EColors.ink)),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, box) {
          final chart = SizedBox(
            width: 170,
            height: 170,
            child: Stack(alignment: Alignment.center, children: [
              PieChart(PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 52,
                startDegreeOffset: -90,
                sections: summary.total == 0
                    ? [PieChartSectionData(value: 1, color: const Color(0xFFE2E8F0), radius: 26, showTitle: false)]
                    : [
                        for (var i = 0; i < entries.length; i++)
                          PieChartSectionData(
                            value: entries[i].value.toDouble(),
                            color: chartPalette[i % chartPalette.length],
                            radius: 26,
                            showTitle: false,
                          ),
                      ],
              )),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${summary.total}',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: EColors.ink)),
                const Text('Tiket', style: TextStyle(fontSize: 12, color: EColors.muted)),
              ]),
            ]),
          );
          final legend = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entries.isEmpty) const Text('Belum ada data.', style: TextStyle(color: EColors.muted)),
              for (var i = 0; i < entries.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    _legendDot(chartPalette[i % chartPalette.length]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(entries[i].key,
                          overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: EColors.text)),
                    ),
                    Text('${entries[i].value}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: EColors.ink)),
                  ]),
                ),
            ],
          );
          if (box.maxWidth >= 380) {
            return Row(children: [chart, const SizedBox(width: 20), Expanded(child: legend)]);
          }
          return Column(children: [chart, const SizedBox(height: 16), legend]);
        }),
      ]),
    );
  }
}

class _LatestCard extends StatelessWidget {
  const _LatestCard({required this.d});
  final StaffDashboard d;

  @override
  Widget build(BuildContext context) => ECard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
              child: Text('Tiket Terbaru',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: EColors.ink)),
            ),
            TextButton(onPressed: () => context.go('/queue'), child: const Text('Lihat Semua')),
          ]),
          const SizedBox(height: 4),
          if (d.latest.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Belum ada tiket.', style: TextStyle(color: EColors.muted)),
            ),
          for (final t in d.latest) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.push('/tickets/${t.id}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    CategoryTile(t.category, size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: EColors.ink)),
                        Text('${t.ticketNumber} · ${Fmt.date(t.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: EColors.muted)),
                      ]),
                    ),
                    const SizedBox(width: 6),
                    ETag.priority(t.priority),
                  ]),
                ),
              ),
            ),
          ],
        ]),
      );
}
