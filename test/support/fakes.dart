import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itsr_radiant/data/admin_repository.dart';
import 'package:itsr_radiant/data/attachment_repository.dart';
import 'package:itsr_radiant/models/attachment_model.dart';
import 'package:itsr_radiant/providers/attachment_provider.dart';
import 'package:itsr_radiant/data/auth_repository.dart';
import 'package:itsr_radiant/data/ticket_repository.dart';
import 'package:itsr_radiant/models/activity_model.dart';
import 'package:itsr_radiant/models/app_notification.dart';
import 'package:itsr_radiant/models/app_settings_model.dart';
import 'package:itsr_radiant/models/category_model.dart';
import 'package:itsr_radiant/models/comment_model.dart';
import 'package:itsr_radiant/models/ticket_model.dart';
import 'package:itsr_radiant/models/ticket_stats.dart';
import 'package:itsr_radiant/models/user_model.dart';
import 'package:itsr_radiant/providers/auth_provider.dart';

final _t0 = DateTime.utc(2026, 11, 1, 8);

UserModel user(String id, String role, {String? name, bool active = true}) =>
    UserModel(
      id: id,
      employeeNumber: id.toUpperCase(),
      email: '$id@example.test',
      fullName: name ?? 'User $id',
      department: 'Ops',
      role: role,
      isActive: active,
      createdAt: _t0,
      updatedAt: _t0,
    );

TicketModel ticket(
  String id, {
  String status = 'open',
  String reporterId = 'emp1',
  String? assignedToId,
  String? resolution,
  String subject = 'Printer broken',
}) => TicketModel(
  id: id,
  ticketNumber: 'ITSR-${id.padLeft(5, '0')}',
  subject: subject,
  description: 'It does not print anything',
  category: 'Hardware',
  priority: 'medium',
  status: status,
  reporterId: reporterId,
  assignedToId: assignedToId,
  resolution: resolution,
  createdAt: _t0,
  updatedAt: _t0,
  reporterName: 'Reporter Name',
  assigneeName: assignedToId == null ? null : 'Tech Name',
);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.profile, this.signInError});
  UserModel? profile;
  Object? signInError;
  final calls = <String>[];
  final _ctrl = StreamController<String?>.broadcast();
  String? _uid;

  void signInAs(UserModel u) {
    profile = u;
    _uid = u.id;
    _ctrl.add(u.id);
  }

  @override
  String? get currentUserId => _uid ?? profile?.id;

  @override
  Stream<String?> userIdChanges() => _ctrl.stream;

  @override
  Future<UserModel?> fetchCurrentProfile() async =>
      (profile?.isActive ?? false) ? profile : null;

  @override
  Future<void> signIn(String employeeNumber, String password) async {
    calls.add('signIn:$employeeNumber');
    if (signInError != null) throw signInError!;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _uid = null;
    profile = null;
    _ctrl.add(null);
  }

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    calls.add('changePassword');
  }
}

class FakeTicketRepository implements TicketRepository {
  FakeTicketRepository({List<TicketModel>? tickets}) : tickets = tickets ?? [];
  List<TicketModel> tickets;
  final calls = <String>[];
  final List<({TicketScope scope, TicketFilter filter, int offset})> fetches =
      [];

  /// When set, fetches with a non-empty search wait for it (simulates a slow request).
  Completer<void>? searchGate;
  List<CategoryModel> categories = const [
    CategoryModel(id: 'c1', name: 'Hardware', isActive: true, sortOrder: 10),
    CategoryModel(id: 'c2', name: 'Network', isActive: true, sortOrder: 20),
  ];
  List<StaffMember> staff = const [
    StaffMember(
      id: 'it1',
      fullName: 'Tech Name',
      employeeNumber: 'IT1',
      role: 'it_support',
    ),
  ];
  List<CommentModel> comments = const [];
  List<ActivityModel> activities = const [];
  Object? failWith;

  @override
  Future<TicketPage> fetchTickets({
    required TicketScope scope,
    required String userId,
    required TicketFilter filter,
    required int offset,
    required int limit,
  }) async {
    fetches.add((scope: scope, filter: filter, offset: offset));
    if (filter.search.isNotEmpty && searchGate != null) {
      await searchGate!.future;
    }
    var list = tickets.where((t) {
      if (scope == TicketScope.mine && t.reporterId != userId) return false;
      if (filter.status != null && t.status != filter.status) return false;
      if (filter.statusIn != null && !filter.statusIn!.contains(t.status)) {
        return false;
      }
      if (filter.search.isNotEmpty &&
          !t.subject.toLowerCase().contains(filter.search.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
    final total = list.length;
    list = list.skip(offset).take(limit).toList();
    return TicketPage(list, total);
  }

  @override
  Future<TicketDetail> fetchDetail(String ticketId) async {
    if (failWith != null) throw failWith!;
    return TicketDetail(
      ticket: tickets.firstWhere((t) => t.id == ticketId),
      comments: comments,
      activities: activities,
    );
  }

  @override
  Future<TicketStats> fetchStats(String scope) async => TicketStats(
    total: tickets.length,
    open: tickets.where((t) => t.status == 'open').length,
  );

  @override
  Future<List<ActivityModel>> fetchRecentActivity({int limit = 10}) async =>
      activities;

  @override
  Future<List<TicketModel>> fetchTicketsInRange({
    required TicketScope scope,
    required String userId,
    required DateTime from,
    required DateTime to,
    int limit = 2000,
  }) async => tickets
      .where(
        (t) =>
            (scope != TicketScope.mine || t.reporterId == userId) &&
            !t.createdAt.isBefore(from) &&
            t.createdAt.isBefore(to),
      )
      .take(limit)
      .toList();

  @override
  Future<List<AppNotification>> fetchNotifications({
    required String userId,
    int limit = 30,
  }) async => const [];

  @override
  Future<List<CategoryModel>> fetchCategories({
    bool includeInactive = false,
  }) async => categories.where((c) => includeInactive || c.isActive).toList();

  @override
  Future<List<StaffMember>> fetchAssignableStaff() async => staff;

  @override
  Future<String> createTicket({
    required String reporterId,
    required String subject,
    required String description,
    required String category,
    required String priority,
  }) async {
    calls.add('create:$reporterId:$subject:$category:$priority');
    if (failWith != null) throw failWith!;
    return 'new-id';
  }

  @override
  Future<void> addComment({
    required String ticketId,
    required String authorId,
    required String content,
    required bool isInternal,
  }) async => calls.add('comment:$ticketId:$content:$isInternal');

  @override
  Future<void> editComment(String commentId, String content) async {
    calls.add('edit:$commentId:$content');
    comments = [
      for (final c in comments)
        c.id == commentId
            ? CommentModel(
                id: c.id,
                ticketId: c.ticketId,
                authorId: c.authorId,
                content: content,
                isInternal: c.isInternal,
                createdAt: c.createdAt,
                editedAt: DateTime.now().toUtc(),
                authorName: c.authorName,
              )
            : c,
    ];
  }

  @override
  Future<void> deleteComment(String commentId) async {
    calls.add('delete:$commentId');
    comments = [
      for (final c in comments)
        c.id == commentId
            ? CommentModel(
                id: c.id,
                ticketId: c.ticketId,
                authorId: c.authorId,
                content: '[dihapus]',
                isInternal: c.isInternal,
                createdAt: c.createdAt,
                deletedAt: DateTime.now().toUtc(),
                authorName: c.authorName,
              )
            : c,
    ];
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
    if (failWith != null) throw failWith!;
    calls.add(
      'update:$ticketId:status=$status:assignee=$assignedToId:unassign=$unassign:resolution=$resolution',
    );
  }

  @override
  Future<void> reporterAction(
    String ticketId,
    String action, {
    String? note,
  }) async => calls.add('reporter:$ticketId:$action:$note');

  @override
  Future<void> kickNotifications() async => calls.add('kick');

  @override
  Future<void> deleteTicket(String ticketId) async {
    if (failWith != null) throw failWith!;
    calls.add('delete:$ticketId');
  }
}

class FakeAdminRepository implements AdminRepository {
  final calls = <String>[];
  List<UserModel> users = [];

  @override
  Future<void> createCategory(
    String name,
    String? description,
    int sortOrder,
  ) async => calls.add('createCategory:$name');
  @override
  Future<void> createUser({
    required String employeeNumber,
    required String fullName,
    required String email,
    required String department,
    required String role,
    String? phoneNumber,
    required String password,
  }) async => calls.add('createUser:$employeeNumber:$role');
  @override
  Future<AppSettingsModel> fetchSettings() async =>
      const AppSettingsModel(notificationsEnabled: true);
  @override
  Future<List<UserModel>> fetchUsers() async => users;
  @override
  Future<void> resetPassword(String userId, String password) async =>
      calls.add('reset:$userId');
  @override
  Future<void> updateCategory(String id, Map<String, dynamic> changes) async =>
      calls.add('updateCategory:$id:$changes');
  @override
  Future<void> updateSettings({
    String? itSupportGroupEmail,
    String? managerEmail,
    required bool notificationsEnabled,
    String? appBaseUrl,
  }) async => calls.add(
    'settings:$itSupportGroupEmail:$managerEmail:$notificationsEnabled',
  );
  @override
  Future<void> updateUser(String userId, Map<String, dynamic> changes) async =>
      calls.add('updateUser:$userId:$changes');
  @override
  Future<Map<String, dynamic>> exportBackup() async {
    calls.add('backup');
    return {'format': 'itsr-backup', 'tables': <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> purgeTickets(String confirmPhrase) async {
    calls.add('purge:$confirmPhrase');
    return {'tickets': 0, 'comments': 0, 'attachments': 0};
  }

  @override
  Future<Map<String, dynamic>> restoreBackup(
    Map<String, dynamic> backup, {
    required String mode,
    required String confirmPhrase,
  }) async {
    calls.add('restore:$mode:$confirmPhrase');
    return {
      'mode': mode,
      'tickets': 1,
      'comments': 0,
      'activity': 0,
      'attachments': 0,
      'categories': 0,
      'skipped_tickets': 0,
    };
  }
}

/// Pumps [child] inside a ProviderScope wired to fakes, at a given screen size.
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  Widget child, {
  required FakeAuthRepository auth,
  FakeTicketRepository? tickets,
  FakeAdminRepository? admin,
  FakeAttachmentRepository? attachments,
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      ticketRepositoryProvider.overrideWithValue(
        tickets ?? FakeTicketRepository(),
      ),
      adminRepositoryProvider.overrideWithValue(admin ?? FakeAdminRepository()),
      attachmentRepositoryProvider.overrideWithValue(
        attachments ?? FakeAttachmentRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// In-memory attachments; [bytes] maps attachment id -> file content.
class FakeAttachmentRepository implements AttachmentRepository {
  FakeAttachmentRepository({
    List<AttachmentModel>? files,
    Map<String, Uint8List>? bytes,
  }) : files = files ?? [],
       bytes = bytes ?? {};
  final List<AttachmentModel> files;
  final Map<String, Uint8List> bytes;

  @override
  Future<List<AttachmentModel>> listAttachments(String ticketId) async =>
      files.where((f) => f.ticketId == ticketId).toList();

  @override
  Future<Uint8List> downloadAttachment(String attachmentId) async =>
      bytes[attachmentId] ?? Uint8List(0);

  @override
  Future<void> deleteAttachment(String attachmentId) async {
    files.removeWhere((f) => f.id == attachmentId);
    bytes.remove(attachmentId);
  }

  @override
  Future<AttachmentModel> uploadAttachment({
    required String ticketId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    required String uploadedBy,
  }) async {
    final a = AttachmentModel(
      id: 'att${files.length + 1}',
      ticketId: ticketId,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: bytes.length,
      uploadedBy: uploadedBy,
      createdAt: DateTime.now().toUtc(),
    );
    files.add(a);
    this.bytes[a.id] = bytes;
    return a;
  }
}
