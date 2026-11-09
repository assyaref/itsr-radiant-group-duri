import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../models/ticket_model.dart';
import '../providers/tickets_provider.dart';
import '../utils/formatters.dart';
import 'common.dart';

/// Search + filters + infinite list for any [TicketScope].
class TicketListView extends ConsumerStatefulWidget {
  const TicketListView({
    super.key,
    required this.scope,
    this.showAssigneeFilter = false,
    this.emptyTitle = 'No tickets yet',
    this.emptyMessage,
    this.emptyAction,
  });

  final TicketScope scope;
  final bool showAssigneeFilter;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget? emptyAction;

  @override
  ConsumerState<TicketListView> createState() => _TicketListViewState();
}

class _TicketListViewState extends ConsumerState<TicketListView> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        ref.read(ticketListProvider(widget.scope).notifier).loadMore();
      }
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
      ref.read(ticketListProvider(widget.scope)).valueOrNull?.filter ??
      const TicketFilter();

  void _apply(TicketFilter f) =>
      ref.read(ticketListProvider(widget.scope).notifier).setFilter(f);

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _apply(_filter.copyWith(search: value.trim())));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ticketListProvider(widget.scope));
    final filter = async.valueOrNull?.filter ?? const TicketFilter();

    final filters = <Widget>[
      _Dropdown(
        label: 'Status',
        value: filter.status,
        options: {for (final s in AppConstants.statuses) s: Fmt.status(s)},
        onChanged: (v) => _apply(filter.copyWith(status: () => v)),
      ),
      _Dropdown(
        label: 'Priority',
        value: filter.priority,
        options: {for (final p in AppConstants.priorities) p: Fmt.priority(p)},
        onChanged: (v) => _apply(filter.copyWith(priority: () => v)),
      ),
      if (widget.showAssigneeFilter)
        _Dropdown(
          label: 'Assignee',
          value: filter.assignee,
          options: const {'unassigned': 'Unassigned', 'me': 'Assigned to me'},
          onChanged: (v) => _apply(filter.copyWith(assignee: () => v)),
        ),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: LayoutBuilder(builder: (context, c) {
            final searchField = TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search number, subject or description',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          _apply(filter.copyWith(search: ''));
                          setState(() {});
                        },
                      ),
              ),
            );
            if (c.maxWidth >= 760) {
              return Row(children: [
                Expanded(flex: 2, child: searchField),
                for (final f in filters) ...[
                  const SizedBox(width: 8),
                  Expanded(child: f),
                ],
              ]);
            }
            return Column(children: [
              searchField,
              const SizedBox(height: 8),
              Row(children: [
                for (var i = 0; i < filters.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: filters[i]),
                ],
              ]),
            ]);
          }),
        ),
        if (async.isLoading && async.hasValue)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            skipLoadingOnRefresh: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () =>
                  ref.read(ticketListProvider(widget.scope).notifier).refresh(),
            ),
            data: (state) {
              if (state.items.isEmpty) {
                final filtered = filter != const TicketFilter();
                return EmptyView(
                  icon: filtered ? Icons.filter_alt_off : Icons.inbox_outlined,
                  title: filtered ? 'No tickets match your filters' : widget.emptyTitle,
                  message: filtered ? 'Try clearing the search or filters.' : widget.emptyMessage,
                  action: filtered ? null : widget.emptyAction,
                );
              }
              return RefreshIndicator(
                onRefresh: () =>
                    ref.read(ticketListProvider(widget.scope).notifier).refresh(),
                child: ListView.separated(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: state.items.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i == state.items.length) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: state.isLoadingMore
                              ? const CircularProgressIndicator()
                              : Text(
                                  'Showing ${state.items.length} of ${state.total}',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                        ),
                      );
                    }
                    return TicketTile(
                      ticket: state.items[i],
                      showReporter: widget.scope != TicketScope.mine,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String? value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
        initialValue: value,
        isExpanded: true,
        isDense: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('All')),
          for (final e in options.entries)
            DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
        ],
        onChanged: onChanged,
      );
}

class TicketTile extends StatelessWidget {
  const TicketTile({super.key, required this.ticket, this.showReporter = false});
  final TicketModel ticket;
  final bool showReporter;

  @override
  Widget build(BuildContext context) {
    final meta = [
      ticket.category,
      if (showReporter && ticket.reporterName != null) 'by ${ticket.reporterName}',
      ticket.assigneeName != null ? 'Assigned: ${ticket.assigneeName}' : 'Unassigned',
      Fmt.relative(ticket.createdAt),
    ].join('  •  ');

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/tickets/${ticket.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(ticket.ticketNumber,
                      style: TextStyle(
                          color: Colors.grey[700], fontWeight: FontWeight.bold)),
                  StatusChip(ticket.status),
                  PriorityChip(ticket.priority),
                ],
              ),
              const SizedBox(height: 8),
              Text(ticket.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
