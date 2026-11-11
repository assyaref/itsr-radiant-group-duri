import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_model.dart';
import '../utils/error_messages.dart';

/// Authentication boundary. Sign-in goes through the `login` Edge Function
/// (employee number + password); the browser never sees another user's data
/// and never holds a service-role key.
abstract class AuthRepository {
  /// Emits the signed-in user id (or null) whenever the session changes.
  Stream<String?> userIdChanges();
  String? get currentUserId;
  Future<void> signIn(String employeeNumber, String password);
  Future<void> signOut();

  /// Profile of the signed-in user, or null if signed out / deactivated.
  Future<UserModel?> fetchCurrentProfile();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);
  final SupabaseClient _client;

  @override
  Stream<String?> userIdChanges() =>
      _client.auth.onAuthStateChange.map((e) => e.session?.user.id).distinct();

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> signIn(String employeeNumber, String password) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'login',
        body: {'employeeNumber': employeeNumber, 'password': password},
      );
    } on FunctionException catch (e) {
      if (e.status == 429) throw const RateLimited();
      // 5xx / gateway problems are not a wrong password: say so, so users do
      // not lock themselves out by retrying a correct password.
      if (e.status >= 500) throw const ServiceUnavailable();
      throw const InvalidCredentials();
    }
    final data = response.data;
    if (data is! Map || data['refresh_token'] is! String) {
      throw const InvalidCredentials();
    }
    await _client.auth.setSession(
      data['refresh_token'] as String,
      accessToken: data['access_token'] is String ? data['access_token'] as String : null,
    );
    // A session alone is not enough: the profile must exist and be active.
    // If it cannot be loaded (network drop right after login), do not leave a
    // half-signed-in session behind.
    UserModel? profile;
    try {
      profile = await fetchCurrentProfile();
    } catch (_) {
      await _safeLocalSignOut();
      rethrow;
    }
    if (profile == null) {
      await _safeLocalSignOut();
      throw const InvalidCredentials();
    }
  }

  Future<void> _safeLocalSignOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // The local session is removed before the server call; ignore offline errors.
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<UserModel?> fetchCurrentProfile() async {
    final id = currentUserId;
    if (id == null) return null;
    final row =
        await _client.from('profiles').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    final profile = UserModel.fromJson(row);
    return profile.isActive ? profile : null;
  }
}
