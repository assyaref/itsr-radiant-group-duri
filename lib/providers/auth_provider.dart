import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/admin_repository.dart';
import '../data/auth_repository.dart';
import '../data/ticket_repository.dart';
import '../models/user_model.dart';

// ---------------------------------------------------------------------------
// Infrastructure (overridden with fakes in tests)
// ---------------------------------------------------------------------------
final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseProvider)),
);

final ticketRepositoryProvider = Provider<TicketRepository>(
  (ref) => SupabaseTicketRepository(ref.watch(supabaseProvider)),
);

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => SupabaseAdminRepository(ref.watch(supabaseProvider)),
);

// ---------------------------------------------------------------------------
// Session + profile
// ---------------------------------------------------------------------------

/// Signed-in auth user id; emits the persisted session immediately on start.
final authUserIdProvider = StreamProvider<String?>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);
  yield repo.currentUserId;
  yield* repo.userIdChanges();
});

/// Profile of the signed-in user (null when signed out or deactivated).
final currentUserProvider = FutureProvider<UserModel?>((ref) async {
  final uid = await ref.watch(authUserIdProvider.future);
  if (uid == null) return null;
  return ref.watch(authRepositoryProvider).fetchCurrentProfile();
});

class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Throws [AppFailure] subclasses with user-safe messages on failure.
  Future<void> signIn(String employeeNumber, String password) async {
    state = const AsyncLoading();
    try {
      await ref.read(authRepositoryProvider).signIn(employeeNumber, password);
      ref.invalidate(currentUserProvider);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    ref.invalidate(currentUserProvider);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);
