import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/app_constants.dart';
import '../../providers/tickets_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';
import '../../widgets/employee_ui.dart';

/// "3. Daftar Tiket" of the employee design: search, filter, status chips.
class EmployeeTicketsScreen extends ConsumerStatefulWidget {
  const EmployeeTicketsScreen({super.key});

  @override
  ConsumerState<EmployeeTicketsScreen> createState() =>
      _EmployeeTicketsScreenState();
}

class _EmployeeTicketsScreenState extends ConsumerState<EmployeeTicketsScreen> {
  static const _scope = TicketScope.mine;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  static const _groups = <(String, List<String>?)>[
    ('Semua', null),
    ('Menunggu', StatusGroups.waiting),
    ('Diproses', StatusGroups.inProgress),
    ('Selesai', StatusGroups.done),
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        ref.read(ticketListProvider(_scope).notifier).loadMore();
      }
    });
    // Keep the search box in sync with a filter kept from an earlier visit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search.text = _filter.search;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  TicketFilter get _filter =>
      ref.read(ticketListProvider(_scope)).valueOrNull?.filter ??
      const TicketFilter();

  void _apply(TicketFilter f) =>
      ref.read(ticketListProvider(_scope).notifier).setFilter(f);

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _apply(_filter.copyWith(search: v.trim())),
    );
  }

  Future<void> _pickPriority() async {
    final current = _filter.priority;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Filter prioritas',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final p in [null, ...AppConstants.priorities])
              ListTile(
                leading: Icon(
                  current == p
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: current == p ? EColors.blue : EColors.muted,
                ),
                title: Text(p == null ? 'Semua prioritas' : Fmt.priority(p)),
                trailing: p == null ? null : ETag.priority(p),
                onTap: () => Navigator.pop(ctx, p ?? ''),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    _apply(_filter.copyWith(priority: () => chosen.isEmpty ? null : chosen));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ticketListProvider(_scope));
    final filter = async.valueOrNull?.filter ?? const TicketFilter();
    final stats = ref.watch(ticketStatsProvider('mine')).valueOrNull;
    final counts = [
      stats?.total,
      stats?.open,
      stats?.inProgress,
      stats == null ? null : stats.resolved + stats.closed,
    ];

    return Scaffold(
      backgroundColor: EColors.page,
      appBar: EHeader(
        title: 'Semua Tiket',
        onBack: () => context.go('/dashboard'),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('ticket_search'),
                        controller: _search,
                        onChanged: _onSearch,
                        textInputAction: TextInputAction.search,
                        decoration: eInput(
                          hint: 'Cari tiket, judul, atau kategori...',
                          prefix: const Icon(
                            Icons.search,
                            color: EColors.muted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Badge(
                      isLabelVisible: filter.priority != null,
                      smallSize: 8,
                      backgroundColor: EColors.blue,
                      child: OutlinedButton(
                        key: const Key('ticket_filter_button'),
                        onPressed: _pickPriority,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: EdgeInsets.zero,
                          side: const BorderSide(color: EColors.line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Icon(
                          Icons.filter_alt_outlined,
                          color: EColors.text,
                          semanticLabel: 'Filter',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < _groups.length; i++) ...[
                        ESegment(
                          key: Key('status_group_${_groups[i].$1}'),
                          label: _groups[i].$1,
                          count: counts[i],
                          selected: TicketFilter.sameStatusGroup(
                            filter.statusIn,
                            _groups[i].$2,
                          ),
                          onTap: () => _apply(
                            filter.copyWith(
                              status: () => null,
                              statusIn: () => _groups[i].$2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              skipLoadingOnRefresh: true,
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () =>
                    ref.read(ticketListProvider(_scope).notifier).refresh(),
              ),
              data: (state) {
                if (state.items.isEmpty) {
                  final filtered =
                      filter.search.isNotEmpty ||
                      filter.priority != null ||
                      filter.statusIn != null;
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(ticketListProvider(_scope).notifier).refresh(),
                    child: ListView(
                      children: [
                        const SizedBox(height: 60),
                        EmptyView(
                          icon: filtered
                              ? Icons.search_off
                              : Icons.inbox_outlined,
                          title: filtered
                              ? 'Tidak ada tiket yang cocok'
                              : 'Anda belum membuat tiket',
                          message: filtered
                              ? 'Coba ubah kata kunci atau filter.'
                              : 'Laporkan masalah IT Anda, tim IT Support siap membantu.',
                          action: filtered
                              ? null
                              : FilledButton.icon(
                                  onPressed: () => context.push('/tickets/new'),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Buat Tiket'),
                                ),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(ticketListProvider(_scope).notifier).refresh(),
                  child: ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: state.items.length + (state.hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => i < state.items.length
                        ? TicketRow(state.items[i])
                        : const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
