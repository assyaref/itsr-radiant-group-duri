import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ticket_repository.dart';
import '../models/activity_model.dart';
import '../models/app_notification.dart';
import '../models/category_model.dart';
import '../models/ticket_model.dart';
import '../models/ticket_stats.dart';
import '../models/ticket_summary.dart';
import 'auth_provider.dart';

export '../data/ticket_repository.dart' show TicketScope, TicketFilter;

// ---------------------------------------------------------------------------
// Paginated ticket lists (one notifier per scope)
// ---------------------------------------------------------------------------
class TicketListState {
  final List<TicketModel> items;
  final int total;
  final TicketFilter filter;
  final bool isLoadingMore;

  const TicketListState({
    this.items = const [],
    this.total = 0,
    this.filter = const TicketFilter(),
    this.isLoadingMore = false,
  });

  bool get hasMore => items.length < total;

  TicketListState copyWith({
    List<TicketModel>? items,
    int? total,
    TicketFilter? filter,
    bool? isLoadingMore,
  }) => TicketListState(
    items: items ?? this.items,
    total: total ?? this.total,
    filter: filter ?? this.filter,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
  );
}

class TicketListNotifier
    extends AutoDisposeFamilyAsyncNotifier<TicketListState, TicketScope> {
  static const pageSize = 20;
  int _requestId = 0;

  @override
  Future<TicketListState> build(TicketScope scope) async {
    // Keep the filter across refreshes/invalidation.
    final filter = state.valueOrNull?.filter ?? const TicketFilter();
    return _load(filter);
  }

  Future<TicketListState> _load(TicketFilter filter) async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return TicketListState(filter: filter);
    final page = await ref
        .read(ticketRepositoryProvider)
        .fetchTickets(
          scope: arg,
          userId: user.id,
          filter: filter,
          offset: 0,
          limit: pageSize,
        );
    return TicketListState(
      items: page.items,
      total: page.total,
      filter: filter,
    );
  }

  /// Applies a new filter once (called from user input, never from build()).
  Future<void> setFilter(TicketFilter filter) async {
    if (state.valueOrNull?.filter == filter && !state.hasError) return;
    final id = ++_requestId;
    state = AsyncLoading<TicketListState>().copyWithPrevious(
      AsyncData(
        state.valueOrNull?.copyWith(filter: filter) ??
            TicketListState(filter: filter),
      ),
    );
    final next = await AsyncValue.guard(() => _load(filter));
    if (id == _requestId) state = next;
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null ||
        !current.hasMore ||
        current.isLoadingMore ||
        state.isLoading) {
      return;
    }
    final id = _requestId;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final user = await ref.read(currentUserProvider.future);
      if (user == null) {
        // Session ended mid-load: clear the spinner instead of leaving it stuck.
        if (id == _requestId) {
          state = AsyncData(current.copyWith(isLoadingMore: false));
        }
        return;
      }
      final page = await ref
          .read(ticketRepositoryProvider)
          .fetchTickets(
            scope: arg,
            userId: user.id,
            filter: current.filter,
            offset: current.items.length,
            limit: pageSize,
          );
      if (id != _requestId) return; // filter changed meanwhile
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...page.items],
          total: page.total,
          isLoadingMore: false,
        ),
      );
    } catch (e, st) {
      if (id == _requestId) {
        state = AsyncError<TicketListState>(
          e,
          st,
        ).copyWithPrevious(AsyncData(current));
      }
    }
  }

  Future<void> refresh() async {
    final filter = state.valueOrNull?.filter ?? const TicketFilter();
    final id = ++_requestId;
    final next = await AsyncValue.guard(() => _load(filter));
    if (id == _requestId) state = next;
  }
}

final ticketListProvider = AsyncNotifierProvider.autoDispose
    .family<TicketListNotifier, TicketListState, TicketScope>(
      TicketListNotifier.new,
    );

// ---------------------------------------------------------------------------
// Read models
// ---------------------------------------------------------------------------

/// 'mine' | 'assigned' | 'all' — counts computed server-side under RLS.
final ticketStatsProvider = FutureProvider.autoDispose
    .family<TicketStats, String>((ref, scope) async {
      final user = await ref.watch(currentUserProvider.future);
      if (user == null) return const TicketStats();
      return ref.watch(ticketRepositoryProvider).fetchStats(scope);
    });

final recentActivityProvider = FutureProvider.autoDispose<List<ActivityModel>>((
  ref,
) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return const [];
  return ref.watch(ticketRepositoryProvider).fetchRecentActivity();
});

final recentMyTicketsProvider = FutureProvider.autoDispose<List<TicketModel>>((
  ref,
) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return const [];
  final page = await ref
      .watch(ticketRepositoryProvider)
      .fetchTickets(
        scope: TicketScope.mine,
        userId: user.id,
        filter: const TicketFilter(),
        offset: 0,
        limit: 5,
      );
  return page.items;
});

final ticketSummaryProvider = FutureProvider.autoDispose
    .family<TicketSummary, SummaryPeriod>((ref, period) async {
      final user = await ref.watch(currentUserProvider.future);
      if (user == null) return TicketSummary.of(const []);
      final tickets = await ref
          .watch(ticketRepositoryProvider)
          .fetchTicketsInRange(
            scope: user.isStaff ? TicketScope.queue : TicketScope.mine,
            userId: user.id,
            from: period.from,
            to: period.to,
          );
      return TicketSummary.of(tickets);
    });

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>(
  (ref) async {
    final user = await ref.watch(currentUserProvider.future);
    if (user == null) return const [];
    return ref
        .watch(ticketRepositoryProvider)
        .fetchNotifications(userId: user.id);
  },
);

final ticketDetailProvider = FutureProvider.autoDispose
    .family<TicketDetail, String>((ref, id) async {
      await ref.watch(currentUserProvider.future);
      return ref.watch(ticketRepositoryProvider).fetchDetail(id);
    });

final categoriesProvider = FutureProvider.autoDispose<List<CategoryModel>>(
  (ref) => ref.watch(ticketRepositoryProvider).fetchCategories(),
);

final assignableStaffProvider = FutureProvider.autoDispose<List<StaffMember>>(
  (ref) => ref.watch(ticketRepositoryProvider).fetchAssignableStaff(),
);

// ---------------------------------------------------------------------------
// Commands: mutate, refresh affected views, nudge email delivery
// ---------------------------------------------------------------------------
class TicketActions {
  TicketActions(this._ref);
  final Ref _ref;

  TicketRepository get _repo => _ref.read(ticketRepositoryProvider);

  void _refresh({String? ticketId, bool kick = true}) {
    _ref.invalidate(ticketListProvider);
    _ref.invalidate(ticketStatsProvider);
    _ref.invalidate(recentActivityProvider);
    _ref.invalidate(recentMyTicketsProvider);
    _ref.invalidate(ticketSummaryProvider);
    _ref.invalidate(notificationsProvider);
    if (ticketId != null) _ref.invalidate(ticketDetailProvider(ticketId));
    if (kick) _repo.kickNotifications();
  }

  /// Sends queued emails now (best effort; the scheduler retries).
  void kickNotifications() => _repo.kickNotifications();

  Future<String> createTicket({
    required String subject,
    required String description,
    required String category,
    required String priority,
    bool notifyNow = true,
  }) async {
    final user = await _ref.read(currentUserProvider.future);
    if (user == null) throw StateError('Not signed in');
    final id = await _repo.createTicket(
      reporterId: user.id,
      subject: subject,
      description: description,
      category: category,
      priority: priority,
    );
    // With attachments to upload, the caller kicks the email after the
    // uploads so the "new ticket" email can show the images.
    _refresh(ticketId: id, kick: notifyNow);
    return id;
  }

  Future<void> addComment(
    String ticketId,
    String content, {
    bool isInternal = false,
  }) async {
    final user = await _ref.read(currentUserProvider.future);
    if (user == null) throw StateError('Not signed in');
    await _repo.addComment(
      ticketId: ticketId,
      authorId: user.id,
      content: content,
      isInternal: isInternal,
    );
    _refresh(ticketId: ticketId);
  }

  Future<void> editComment(
    String ticketId,
    String commentId,
    String content,
  ) async {
    await _repo.editComment(commentId, content);
    _refresh(ticketId: ticketId);
  }

  Future<void> deleteComment(String ticketId, String commentId) async {
    await _repo.deleteComment(commentId);
    _refresh(ticketId: ticketId);
  }

  Future<void> acceptTicket(String ticketId) async {
    final user = await _ref.read(currentUserProvider.future);
    if (user == null) throw StateError('Not signed in');
    await _repo.updateTicket(ticketId, assignedToId: user.id);
    _refresh(ticketId: ticketId);
  }

  /// Invalidates every cached ticket list / stat (e.g. after a purge).
  void refreshAll() {
    _ref.invalidate(ticketDetailProvider);
    _refresh();
  }

  Future<void> deleteTicket(String ticketId) async {
    await _repo.deleteTicket(ticketId);
    // The open detail screen navigates away itself; only lists are refreshed.
    _refresh();
  }

  Future<void> assignTicket(String ticketId, String staffId) async {
    await _repo.updateTicket(ticketId, assignedToId: staffId);
    _refresh(ticketId: ticketId);
  }

  Future<void> changeStatus(
    String ticketId,
    String status, {
    String? resolution,
  }) async {
    // "Return to queue" (-> open) also releases the current assignee.
    await _repo.updateTicket(
      ticketId,
      status: status,
      resolution: resolution,
      unassign: status == 'open',
    );
    _refresh(ticketId: ticketId);
  }

  Future<void> changePriority(String ticketId, String priority) async {
    await _repo.updateTicket(ticketId, priority: priority);
    _refresh(ticketId: ticketId);
  }

  Future<void> reopen(String ticketId, String reason) async {
    await _repo.reporterAction(ticketId, 'reopen', note: reason);
    _refresh(ticketId: ticketId);
  }

  Future<void> confirmClose(String ticketId) async {
    await _repo.reporterAction(ticketId, 'close');
    _refresh(ticketId: ticketId);
  }
}

final ticketActionsProvider = Provider<TicketActions>(TicketActions.new);
