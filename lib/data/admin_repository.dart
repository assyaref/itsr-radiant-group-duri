import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_settings_model.dart';
import '../models/user_model.dart';

/// Administrator operations. Profile/account changes go through the
/// `admin-users` Edge Function, which re-verifies that the caller is an active
/// administrator server-side. Categories and settings are protected by RLS.
abstract class AdminRepository {
  Future<List<UserModel>> fetchUsers();
  Future<void> createUser({
    required String employeeNumber,
    required String fullName,
    required String email,
    required String department,
    required String role,
    String? phoneNumber,
    required String password,
  });
  Future<void> updateUser(String userId, Map<String, dynamic> changes);
  Future<void> resetPassword(String userId, String password);

  Future<void> createCategory(String name, String? description, int sortOrder);
  Future<void> updateCategory(String id, Map<String, dynamic> changes);

  Future<AppSettingsModel> fetchSettings();
  Future<void> updateSettings({
    String? itSupportGroupEmail,
    String? managerEmail,
    required bool notificationsEnabled,
    String? appBaseUrl,
  });

  /// Full JSON export of the application data (administrator + superadmin).
  Future<Map<String, dynamic>> exportBackup();

  /// Deletes ALL ticket data. [confirmPhrase] must be `HAPUS SEMUA DATA`.
  /// Returns the deleted counts (tickets, comments, attachments).
  Future<Map<String, dynamic>> purgeTickets(String confirmPhrase);

  /// Restores ticket data from an [exportBackup] document.
  /// [mode] is `merge` or `replace`; [confirmPhrase] must be `RESTORE DATA`.
  Future<Map<String, dynamic>> restoreBackup(
    Map<String, dynamic> backup, {
    required String mode,
    required String confirmPhrase,
  });
}

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._client);
  final SupabaseClient _client;

  Future<void> _call(Map<String, dynamic> body) async {
    await _client.functions.invoke('admin-users', body: body);
  }

  @override
  Future<List<UserModel>> fetchUsers() async {
    final rows = await _client.from('profiles').select().order('full_name');
    return rows.map(UserModel.fromJson).toList();
  }

  @override
  Future<void> createUser({
    required String employeeNumber,
    required String fullName,
    required String email,
    required String department,
    required String role,
    String? phoneNumber,
    required String password,
  }) => _call({
    'action': 'create',
    'employee_number': employeeNumber,
    'full_name': fullName,
    'email': email,
    'department': department,
    'role': role,
    'phone_number': phoneNumber,
    'password': password,
  });

  @override
  Future<void> updateUser(String userId, Map<String, dynamic> changes) =>
      _call({'action': 'update', 'user_id': userId, ...changes});

  @override
  Future<void> resetPassword(String userId, String password) => _call({
    'action': 'reset_password',
    'user_id': userId,
    'password': password,
  });

  @override
  Future<void> createCategory(
    String name,
    String? description,
    int sortOrder,
  ) async {
    await _client.from('categories').insert({
      'name': name.trim(),
      'description': description?.trim(),
      'sort_order': sortOrder,
    });
  }

  @override
  Future<void> updateCategory(String id, Map<String, dynamic> changes) async {
    final rows = await _client
        .from('categories')
        .update(changes)
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) {
      throw const PostgrestException(message: 'denied', code: '42501');
    }
  }

  @override
  Future<AppSettingsModel> fetchSettings() async {
    final row = await _client
        .from('app_settings')
        .select()
        .eq('id', true)
        .single();
    return AppSettingsModel.fromJson(row);
  }

  @override
  Future<void> updateSettings({
    String? itSupportGroupEmail,
    String? managerEmail,
    required bool notificationsEnabled,
    String? appBaseUrl,
  }) async {
    String? blankToNull(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();
    final rows = await _client
        .from('app_settings')
        .update({
          'it_support_group_email': blankToNull(itSupportGroupEmail),
          'manager_email': blankToNull(managerEmail),
          'notifications_enabled': notificationsEnabled,
          'app_base_url': blankToNull(appBaseUrl),
        })
        .eq('id', true)
        .select('id');
    if (rows.isEmpty) {
      throw const PostgrestException(message: 'denied', code: '42501');
    }
  }

  @override
  Future<Map<String, dynamic>> exportBackup() async {
    final res = await _client.rpc('admin_backup');
    return Map<String, dynamic>.from(res as Map);
  }

  @override
  Future<Map<String, dynamic>> purgeTickets(String confirmPhrase) async {
    final res = await _client.rpc(
      'admin_purge_tickets',
      params: {'p_confirm': confirmPhrase},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  @override
  Future<Map<String, dynamic>> restoreBackup(
    Map<String, dynamic> backup, {
    required String mode,
    required String confirmPhrase,
  }) async {
    final res = await _client.rpc(
      'admin_restore',
      params: {'p_backup': backup, 'p_mode': mode, 'p_confirm': confirmPhrase},
    );
    return Map<String, dynamic>.from(res as Map);
  }
}
