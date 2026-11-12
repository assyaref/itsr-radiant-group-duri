import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../models/ticket_model.dart';
import '../providers/auth_provider.dart';
import '../providers/tickets_provider.dart';
import '../utils/error_messages.dart';
import '../utils/formatters.dart';
import '../widgets/common.dart';
import '../widgets/employee_ui.dart';

/// "2. Manajemen Tiket": every ticket IT Support / administrators can see
/// (RLS-enforced) with status tabs, search and category / priority /
/// technician filters. Desktop shows a table, phones a card list.
class ITSupportQueueScreen extends ConsumerStatefulWidget {
  const ITSupportQueueScreen({super.key, this.initialSearch});
  final String? initialSearch;

  @override
  ConsumerState<ITSupportQueueScreen> createState() => _ITSupportQueueScreenState();
}

class _ITSupportQueueScreenState extends ConsumerState<ITSupportQueueScreen> {
  static const _scope = TicketScope.queue;
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final q = widget.initialSearch?.trim() ?? '';
      if (q.isNotEmpty) {
        _search.text = q;
        _apply(_filter.copyWith(search: q));
      } else {
        _search.text = _filter.search;
      }
    });
  }

  @override
  void didUpdateWidget(ITSupportQueueScreen old) {
    super.didUpdateWidget(old);
    final q = widget.initialSearch?.trim() ?? '';
    if (q != (old.initialSearch?.trim() ?? '') && q.isNotEmpty) {
      _search.text = q;
      _apply(_filter.copyWith(search: q));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  TicketFilter get _filter => ref.read(ticketListProvider(_scope)).valueOrNull?.filter ?? const TicketFilter();
  void _apply(TicketFilter f) => ref.read(ticketListProvider(_scope).notifier).setFilter(f);

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _apply(_filter.copyWith(search: v.trim())));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ticketListProvider(_scope));
    final filter = async.valueOrNull?.filter ?? const TicketFilter();
    final counts = ref.watch(queueTabCountsProvider).valueOrNull;
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final staff = ref.watch(assignableStaffProvider).valueOrNull ?? const [];
    final desktop = isDesktop(context);

    final tabs = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var i = 0; i < QueueTabs.tabs.length; i++) ...[
          ESegment(
            key: Key('queue_tab_${QueueTabs.tabs[i].$1}'),
            label: QueueTabs.tabs[i].$1,
            count: counts?[i],
            selected: filter.status == null && TicketFilter.sameStatusGroup(filter.statusIn, QueueTabs.tabs[i].$2),
            onTap: () => _apply(filter.copyWith(status: () => null, statusIn: () => QueueTabs.tabs[i].$2)),
          ),
          const SizedBox(width: 8),
        ],
      ]),
    );

    Widget dropdown<T>({
      required Key key,
      required String hint,
      required T? value,
      required List<(T, String)> options,
      required ValueChanged<T?> onChanged,
    }) =>
        SizedBox(
          width: desktop ? 190 : double.infinity,
          child: DropdownButtonFormField<T?>(
            key: key,
            initialValue: value,
            isExpanded: true,
            decoration: eInput(),
            hint: Text(hint, style: const TextStyle(fontSize: 13.5)),
            items: [
              DropdownMenuItem<T?>(value: null, child: Text(hint, style: const TextStyle(fontSize: 13.5))),
              for (final (v, label) in options)
                DropdownMenuItem<T?>(
                    value: v, child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))),
            ],
            onChanged: onChanged,
          ),
        );

    final searchField = TextField(
      key: const Key('queue_search'),
      controller: _search,
      onChanged: _onSearch,
      decoration: eInput(
        hint: 'Cari nomor tiket, judul, atau deskripsi…',
        prefix: const Icon(Icons.search, color: EColors.muted),
      ),
    );
    final filters = [
      dropdown<String>(
        key: const Key('filter_category'),
        hint: 'Semua Kategori',
        value: filter.category,
        options: [for (final c in categories) (c.name, c.name)],
        onChanged: (v) => _apply(filter.copyWith(category: () => v)),
      ),
      dropdown<String>(
        key: const Key('filter_priority'),
        hint: 'Semua Prioritas',
        value: filter.priority,
        options: [for (final p in AppConstants.priorities) (p, Fmt.priority(p))],
        onChanged: (v) => _apply(filter.copyWith(priority: () => v)),
      ),
      dropdown<String>(
        key: const Key('filter_technician'),
        hint: 'Semua Teknisi',
        value: filter.assignee == 'unassigned' ? '__none' : filter.assigneeId,
        options: [('__none', 'Belum ditugaskan'), for (final s in staff) (s.id, s.fullName)],
        onChanged: (v) => _apply(filter.copyWith(
          assignee: () => v == '__none' ? 'unassigned' : null,
          assigneeId: () => v == '__none' ? null : v,
        )),
      ),
    ];

    final list = async.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox(height: 240, child: LoadingView()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.read(ticketListProvider(_scope).notifier).refresh()),
      data: (state) {
        if (state.items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: EmptyView(
              icon: Icons.inbox_outlined,
              title: 'Tidak ada tiket',
              message: 'Coba ubah tab, kata kunci, atau filter.',
            ),
          );
        }
        final more = state.hasMore
            ? Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: state.isLoadingMore
                      ? const CircularProgressIndicator()
                      : OutlinedButton(
                          onPressed: () => ref.read(ticketListProvider(_scope).notifier).loadMore(),
                          child: Text('Muat lebih banyak (${state.items.length} dari ${state.total})'),
                        ),
                ),
              )
            : const SizedBox.shrink();
        if (desktop) {
          return Column(children: [_TicketTable(items: state.items), more]);
        }
        return Column(children: [
          for (final t in state.items) ...[TicketRow(t), const SizedBox(height: 8)],
          more,
        ]);
      },
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(queueTabCountsProvider);
        await ref.read(ticketListProvider(_scope).notifier).refresh();
      },
      child: ListView(
        padding: EdgeInsets.all(desktop ? 24 : 16),
        children: [
          if (!desktop) const SizedBox(height: 8),
          Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Manajemen Tiket', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: EColors.ink)),
                SizedBox(height: 2),
                Text('Kelola, pantau, dan tindak lanjuti seluruh tiket IT Support',
                    style: TextStyle(color: EColors.muted, fontSize: 13)),
              ]),
            ),
            FilledButton.icon(
              key: const Key('queue_create_ticket'),
              onPressed: () => context.push('/tickets/new'),
              style: FilledButton.styleFrom(backgroundColor: EColors.blue),
              icon: const Icon(Icons.add),
              label: Text(desktop ? 'Buat Tiket' : 'Buat'),
            ),
          ]),
          const SizedBox(height: 16),
          ECard(
            padding: EdgeInsets.all(desktop ? 18 : 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              tabs,
              const SizedBox(height: 14),
              if (desktop)
                Row(children: [
                  Expanded(child: searchField),
                  for (final f in filters) ...[const SizedBox(width: 10), f],
                ])
              else ...[
                searchField,
                const SizedBox(height: 10),
                for (final f in filters) ...[f, const SizedBox(height: 8)],
              ],
              const SizedBox(height: 14),
              list,
            ]),
          ),
        ],
      ),
    );
  }
}

class _TicketTable extends ConsumerWidget {
  const _TicketTable({required this.items});
  final List<TicketModel> items;

  Future<void> _accept(BuildContext context, WidgetRef ref, TicketModel t) async {
    try {
      await ref.read(ticketActionsProvider).acceptTicket(t.id);
      if (context.mounted) showSnack(context, '${t.ticketNumber} sekarang Anda tangani');
    } catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider).valueOrNull;
    const head = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: EColors.ink);
    const cell = TextStyle(fontSize: 13, color: EColors.text);
    Widget c(String s, {TextStyle style = cell}) =>
        Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    return LayoutBuilder(builder: (context, box) {
      final table = DataTable(
        headingRowHeight: 42,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 52,
        horizontalMargin: 12,
        columnSpacing: 18,
        headingRowColor: const WidgetStatePropertyAll(Color(0xFFF8FAFC)),
        border: const TableBorder(horizontalInside: BorderSide(color: Color(0xFFF1F5F9))),
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('No. Tiket', style: head)),
          DataColumn(label: Text('Judul', style: head)),
          DataColumn(label: Text('Kategori', style: head)),
          DataColumn(label: Text('Prioritas', style: head)),
          DataColumn(label: Text('Status', style: head)),
          DataColumn(label: Text('Pelapor', style: head)),
          DataColumn(label: Text('Teknisi', style: head)),
          DataColumn(label: Text('Dibuat', style: head)),
          DataColumn(label: Text('Aksi', style: head)),
        ],
        rows: [
          for (final t in items)
            DataRow(
              onSelectChanged: (_) => context.push('/tickets/${t.id}'),
              cells: [
                DataCell(c(t.ticketNumber, style: cell.copyWith(fontWeight: FontWeight.w600, color: EColors.blue))),
                DataCell(ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: c(t.subject, style: cell.copyWith(color: EColors.ink, fontWeight: FontWeight.w600)),
                )),
                DataCell(c(t.category)),
                DataCell(ETag.priority(t.priority)),
                DataCell(ETag.status(t.status)),
                DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130), child: c(t.reporterName ?? '—'))),
                DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130), child: c(t.assigneeName ?? '—'))),
                DataCell(c(Fmt.date(t.createdAt))),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Lihat ${t.ticketNumber}',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context.push('/tickets/${t.id}'),
                    icon: const Icon(Icons.visibility_outlined, size: 20, color: EColors.text),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Aksi lainnya',
                    icon: const Icon(Icons.more_vert, size: 20, color: EColors.text),
                    onSelected: (v) {
                      if (v == 'open') context.push('/tickets/${t.id}');
                      if (v == 'accept') _accept(context, ref, t);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'open', child: Text('Buka detail')),
                      if (!t.isFinished && t.assignedToId != me?.id)
                        PopupMenuItem(
                          value: 'accept',
                          child: Text(t.assignedToId == null ? 'Ambil tiket' : 'Ambil alih tiket'),
                        ),
                    ],
                  ),
                ])),
              ],
            ),
        ],
      );
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(constraints: BoxConstraints(minWidth: box.maxWidth), child: table),
      );
    });
  }
}
