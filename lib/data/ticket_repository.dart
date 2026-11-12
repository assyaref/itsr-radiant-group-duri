import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity_model.dart';
import '../models/app_notification.dart';
import '../models/category_model.dart';
import '../models/comment_model.dart';
import '../models/ticket_model.dart';
import '../models/ticket_stats.dart';
import '../utils/validators.dart';

/// Which tickets a list shows. RLS on the server is what actually restricts
/// rows; the scope only narrows what the caller is allowed to see.
enum TicketScope { mine, assignedToMe, queue }

class TicketFilter {
  final String search;
  final String? status;
  final String? priority;

  /// Only for [TicketScope.queue]: 'unassigned', 'me', or null (all).
  final String? assignee;

  /// Several statuses at once (e.g. "Selesai" = resolved + closed).
  /// Ignored when [status] is set.
  final List<String>? statusIn;

  const TicketFilter({
    this.search = '',
    this.status,
    this.priority,
    this.assignee,
    this.statusIn,
  });

  TicketFilter copyWith({
    String? search,
    String? Function()? status,
    String? Function()? priority,
    String? Function()? assignee,
    List<String>? Function()? statusIn,
  }) => TicketFilter(
    search: search ?? this.search,
    status: status != null ? status() : this.status,
    priority: priority != null ? priority() : this.priority,
    assignee: assignee != null ? assignee() : this.assignee,
    statusIn: statusIn != null ? statusIn() : this.statusIn,
  );

  @override
  bool operator ==(Object other) =>
      other is TicketFilter &&
      other.search == search &&
      other.status == status &&
      other.priority == priority &&
      other.assignee == assignee &&
      _sameList(other.statusIn, statusIn);

  /// Whether two status groups are the same (null = "all").
  static bool sameStatusGroup(List<String>? a, List<String>? b) =>
      _sameList(a, b);

  static bool _sameList(List<String>? a, List<String>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    search,
    status,
    priority,
    assignee,
    Object.hashAll(statusIn ?? const []),
  );
}

class TicketPage {
  final List<TicketModel> items;
  final int total;
  const TicketPage(this.items, this.total);
}

abstract class TicketRepository {
  Future<TicketPage> fetchTickets({
    required TicketScope scope,
    required String userId,
    required TicketFilter filter,
    required int offset,
    required int limit,
  });
  Future<TicketDetail> fetchDetail(String ticketId);
  Future<TicketStats> fetchStats(String scope);
  Future<List<ActivityModel>> fetchRecentActivity({int limit = 10});
  Future<List<CategoryModel>> fetchCategories({bool includeInactive = false});
  Future<List<StaffMember>> fetchAssignableStaff();

  /// Returns the new ticket's id.
  Future<String> createTicket({
    required String reporterId,
    required String subject,
    required String description,
    required String category,
    required String priority,
  });
  Future<void> addComment({
    required String ticketId,
    required String authorId,
    required String content,
    required bool isInternal,
  });

  /// Staff-only workflow update. Only non-null fields are sent.
  Future<void> updateTicket(
    String ticketId, {
    String? status,
    String? priority,
    String? assignedToId,
    bool unassign = false,
    String? resolution,
  });

  /// Reporter actions: 'reopen' (needs [note]) or 'close'.
  Future<void> reporterAction(String ticketId, String action, {String? note});

  /// Ask the server to deliver queued email notifications. Never throws.
  Future<void> kickNotifications();

  /// Tickets created in [from, to) for the summary report: the caller's own
  /// ([TicketScope.mine]) or every ticket they can see (staff, any other
  /// scope). Capped at [limit] rows; newest first.
  Future<List<TicketModel>> fetchTicketsInRange({
    required TicketScope scope,
    required String userId,
    required DateTime from,
    required DateTime to,
    int limit = 2000,
  });

  /// In-app notifications for [userId]: ticket events and other people's
  /// comments on tickets the caller can see (RLS-scoped), newest first.
  Future<List<AppNotification>> fetchNotifications({
    required String userId,
    int limit = 30,
  });
}

class SupabaseTicketRepository implements TicketRepository {
  SupabaseTicketRepository(this._client);
  final SupabaseClient _client;

  static const _ticketSelect =
      '*, reporter:profiles!tickets_reporter_id_fkey(full_name), '
      'assignee:profiles!tickets_assigned_to_id_fkey(full_name)';

  @override
  Future<TicketPage> fetchTickets({
    required TicketScope scope,
    required String userId,
    required TicketFilter filter,
    required int offset,
    required int limit,
  }) async {
    var q = _client.from('tickets').select(_ticketSelect);
    switch (scope) {
      case TicketScope.mine:
        q = q.eq('reporter_id', userId);
      case TicketScope.assignedToMe:
        q = q.eq('assigned_to_id', userId);
      case TicketScope.queue:
        if (filter.assignee == 'unassigned') {
          q = q.isFilter('assigned_to_id', null);
        }
        if (filter.assignee == 'me') q = q.eq('assigned_to_id', userId);
    }
    if (filter.status != null) {
      q = q.eq('status', filter.status!);
    } else if (filter.statusIn != null && filter.statusIn!.isNotEmpty) {
      q = q.inFilter('status', filter.statusIn!);
    }
    if (filter.priority != null) q = q.eq('priority', filter.priority!);
    final term = Validators.sanitizeSearch(filter.search);
    if (term.isNotEmpty) {
      q = q.or(
        'subject.ilike.*$term*,ticket_number.ilike.*$term*,'
        'description.ilike.*$term*',
      );
    }
    final res = await q
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1)
        .count(CountOption.exact);
    final items = res.data.map(TicketModel.fromJson).toList();
    return TicketPage(items, res.count);
  }

  @override
  Future<TicketDetail> fetchDetail(String ticketId) async {
    final ticketRow = await _client
        .from('tickets')
        .select(_ticketSelect)
        .eq('id', ticketId)
        .maybeSingle();
    if (ticketRow == null) {
      // RLS hides tickets the caller may not see: indistinguishable from missing.
      throw const PostgrestException(message: 'not found', code: 'PGRST116');
    }
    final results = await Future.wait([
      _client
          .from('ticket_comments')
          .select('*, author:profiles(full_name)')
          .eq('ticket_id', ticketId)
          .order('created_at'),
      _client
          .from('ticket_activity_log')
          .select('*, actor:profiles(full_name)')
          .eq('ticket_id', ticketId)
          .order('created_at'),
    ]);
    return TicketDetail(
      ticket: TicketModel.fromJson(ticketRow),
      comments: results[0].map(CommentModel.fromJson).toList(),
      activities: results[1].map(ActivityModel.fromJson).toList(),
    );
  }

  @override
  Future<TicketStats> fetchStats(String scope) async {
    final rows = await _client.rpc('ticket_stats', params: {'p_scope': scope});
    final Object? first = rows is List
        ? (rows.isEmpty ? null : rows.first)
        : rows;
    return first is Map
        ? TicketStats.fromJson(Map<String, dynamic>.from(first))
        : const TicketStats();
  }

  @override
  Future<List<ActivityModel>> fetchRecentActivity({int limit = 10}) async {
    final rows = await _client
        .from('ticket_activity_log')
        .select(
          '*, actor:profiles(full_name), ticket:tickets(ticket_number,subject)',
        )
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(ActivityModel.fromJson).toList();
  }

  @override
  Future<List<CategoryModel>> fetchCategories({
    bool includeInactive = false,
  }) async {
    var q = _client.from('categories').select();
    if (!includeInactive) q = q.eq('is_active', true);
    final rows = await q.order('sort_order').order('name');
    return rows.map(CategoryModel.fromJson).toList();
  }

  @override
  Future<List<StaffMember>> fetchAssignableStaff() async {
    final rows = await _client.rpc('assignable_staff');
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((r) => StaffMember.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  @override
  Future<String> createTicket({
    required String reporterId,
    required String subject,
    required String description,
    required String category,
    required String priority,
  }) async {
    // Only user-supplied columns: number/status/timestamps are server-owned.
    final row = await _client
        .from('tickets')
        .insert({
          'reporter_id': reporterId,
          'subject': subject.trim(),
          'description': description.trim(),
          'category': category,
          'priority': priority,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  @override
  Future<void> addComment({
    required String ticketId,
    required String authorId,
    required String content,
    required bool isInternal,
  }) async {
    await _client.from('ticket_comments').insert({
      'ticket_id': ticketId,
      'author_id': authorId,
      'content': content.trim(),
      'is_internal': isInternal,
    });
  }

  @override
  Future<void> updateTicket(
    String ticketId, {
    String? status,
    String? priority,
    String? assignedToId,
    bool unassign = false,
    String? resolution,
  }) async {
    final changes = <String, dynamic>{
      'status': ?status,
      'priority': ?priority,
      'assigned_to_id': ?assignedToId,
      'resolution': ?resolution,
    };
    if (unassign) changes['assigned_to_id'] = null;
    if (changes.isEmpty) return;
    final rows = await _client
        .from('tickets')
        .update(changes)
        .eq('id', ticketId)
        .select('id');
    if (rows.isEmpty) {
      throw const PostgrestException(message: 'denied', code: '42501');
    }
  }

  @override
  Future<void> reporterAction(
    String ticketId,
    String action, {
    String? note,
  }) async {
    await _client.rpc(
      'reporter_ticket_action',
      params: {'p_ticket_id': ticketId, 'p_action': action, 'p_note': note},
    );
  }

  @override
  Future<List<TicketModel>> fetchTicketsInRange({
    required TicketScope scope,
    required String userId,
    required DateTime from,
    required DateTime to,
    int limit = 2000,
  }) async {
    var q = _client
        .from('tickets')
        .select(_ticketSelect)
        .gte('created_at', from.toUtc().toIso8601String())
        .lt('created_at', to.toUtc().toIso8601String());
    if (scope == TicketScope.mine) q = q.eq('reporter_id', userId);
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return rows.map(TicketModel.fromJson).toList();
  }

  @override
  Future<List<AppNotification>> fetchNotifications({
    required String userId,
    int limit = 30,
  }) async {
    final results = await Future.wait([
      _client
          .from('ticket_activity_log')
          .select(
            '*, actor:profiles(full_name), ticket:tickets(ticket_number,subject)',
          )
          .order('created_at', ascending: false)
          .limit(limit),
      _client
          .from('ticket_comments')
          .select(
            'id, ticket_id, author_id, created_at, author:profiles(full_name), '
            'ticket:tickets(ticket_number,subject)',
          )
          .neq('author_id', userId)
          .order('created_at', ascending: false)
          .limit(limit),
    ]);
    final items = <AppNotification>[
      for (final row in results[0])
        AppNotification.fromActivity(ActivityModel.fromJson(row)),
      for (final row in results[1]) AppNotification.fromCommentRow(row),
    ]..sort((a, b) => b.time.compareTo(a.time));
    return items.take(limit).toList();
  }

  @override
  Future<void> kickNotifications() async {
    try {
      await _client.functions.invoke('send-notifications');
    } catch (_) {
      // Best effort: rows stay queued and are retried by the scheduler.
    }
  }
}
