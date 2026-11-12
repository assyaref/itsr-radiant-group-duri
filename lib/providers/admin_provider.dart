import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings_model.dart';
import '../models/category_model.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';
import 'tickets_provider.dart';

final usersProvider = FutureProvider.autoDispose<List<UserModel>>(
  (ref) => ref.watch(adminRepositoryProvider).fetchUsers(),
);

final allCategoriesProvider = FutureProvider.autoDispose<List<CategoryModel>>(
  (ref) => ref.watch(ticketRepositoryProvider).fetchCategories(includeInactive: true),
);

final appSettingsProvider = FutureProvider.autoDispose<AppSettingsModel>(
  (ref) => ref.watch(adminRepositoryProvider).fetchSettings(),
);

class AdminActions {
  AdminActions(this._ref);
  final Ref _ref;

  Future<void> createUser({
    required String employeeNumber,
    required String fullName,
    required String email,
    required String department,
    required String role,
    String? phoneNumber,
    required String password,
    bool refresh = true,
  }) async {
    await _ref.read(adminRepositoryProvider).createUser(
          employeeNumber: employeeNumber,
          fullName: fullName,
          email: email,
          department: department,
          role: role,
          phoneNumber: phoneNumber,
          password: password,
        );
    // Bulk import refreshes once at the end instead of after every row.
    if (refresh) _ref.invalidate(usersProvider);
  }

  Future<void> updateUser(String userId, Map<String, dynamic> changes) async {
    await _ref.read(adminRepositoryProvider).updateUser(userId, changes);
    _ref.invalidate(usersProvider);
    _ref.invalidate(assignableStaffProvider);
    // If admins edit themselves, refresh the session profile too.
    _ref.invalidate(currentUserProvider);
  }

  Future<void> resetPassword(String userId, String password) =>
      _ref.read(adminRepositoryProvider).resetPassword(userId, password);

  Future<void> createCategory(String name, String? description, int sortOrder) async {
    await _ref.read(adminRepositoryProvider).createCategory(name, description, sortOrder);
    _ref.invalidate(allCategoriesProvider);
    _ref.invalidate(categoriesProvider);
  }

  Future<void> updateCategory(String id, Map<String, dynamic> changes) async {
    await _ref.read(adminRepositoryProvider).updateCategory(id, changes);
    _ref.invalidate(allCategoriesProvider);
    _ref.invalidate(categoriesProvider);
  }

  Future<void> saveSettings({
    String? itSupportGroupEmail,
    String? managerEmail,
    required bool notificationsEnabled,
    String? appBaseUrl,
  }) async {
    await _ref.read(adminRepositoryProvider).updateSettings(
          itSupportGroupEmail: itSupportGroupEmail,
          managerEmail: managerEmail,
          notificationsEnabled: notificationsEnabled,
          appBaseUrl: appBaseUrl,
        );
    _ref.invalidate(appSettingsProvider);
  }
}

final adminActionsProvider = Provider<AdminActions>(AdminActions.new);
