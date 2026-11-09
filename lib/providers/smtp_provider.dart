import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/smtp_repository.dart';
import '../models/smtp_config_model.dart';
import 'auth_provider.dart';

/// Provider for the SMTP repository.
final smtpRepositoryProvider = Provider<SmtpRepository>((ref) {
  return SupabaseSmtpRepository(ref.watch(supabaseProvider));
});

/// Fetches SMTP configuration status from the backend.
final smtpConfigProvider = FutureProvider.autoDispose<SmtpConfigModel>((ref) {
  return ref.watch(smtpRepositoryProvider).fetchSmtpStatus();
});

class SmtpActions {
  SmtpActions(this._ref);
  final Ref _ref;

  Future<void> saveSmtpConfig(SmtpConfigInput config) async {
    await _ref.read(smtpRepositoryProvider).saveSmtpConfig(config);
    _ref.invalidate(smtpConfigProvider);
  }

  Future<void> removeSmtpCredential() async {
    await _ref.read(smtpRepositoryProvider).removeSmtpCredential();
    _ref.invalidate(smtpConfigProvider);
  }

  Future<void> testSmtpConnection({
    required String host,
    required int port,
    required bool secure,
    required String username,
    required String password,
  }) async {
    await _ref.read(smtpRepositoryProvider).testSmtpConnection(
      host: host,
      port: port,
      secure: secure,
      username: username,
      password: password,
    );
    _ref.invalidate(smtpConfigProvider);
  }

  Future<void> sendTestEmail({
    required String host,
    required int port,
    required bool secure,
    required String username,
    required String password,
    String? senderName,
    required String senderEmail,
    required String recipient,
    required bool confirm,
  }) async {
    await _ref.read(smtpRepositoryProvider).sendTestEmail(
      host: host,
      port: port,
      secure: secure,
      username: username,
      password: password,
      senderName: senderName,
      senderEmail: senderEmail,
      recipient: recipient,
      confirm: confirm,
    );
    _ref.invalidate(smtpConfigProvider);
  }
}

final smtpActionsProvider = Provider<SmtpActions>((ref) => SmtpActions(ref));