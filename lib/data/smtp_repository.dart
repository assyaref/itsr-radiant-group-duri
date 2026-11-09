import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/smtp_config_model.dart';

/// Repository for SMTP configuration and notification management.
/// All writes go through the `smtp-config` Edge Function, which verifies the
/// caller is an active administrator server-side. Reads also go through the
/// Edge Function so that the SMTP password is never exposed to the client.
abstract class SmtpRepository {
  Future<SmtpConfigModel> fetchSmtpStatus();
  Future<void> saveSmtpConfig(SmtpConfigInput config);
  Future<void> removeSmtpCredential();
  Future<void> testSmtpConnection({
    required String host,
    required int port,
    required bool secure,
    required String username,
    required String password,
  });
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
  });
}

class SupabaseSmtpRepository implements SmtpRepository {
  SupabaseSmtpRepository(this._client);
  final SupabaseClient _client;

  static const _function = 'smtp-config';

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final response = await _client.functions.invoke(_function, body: body);
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<SmtpConfigModel> fetchSmtpStatus() async {
    final data = await _invoke({'action': 'status'});
    return SmtpConfigModel.fromJson(data);
  }

  @override
  Future<void> saveSmtpConfig(SmtpConfigInput config) async {
    await _invoke({
      'action': 'save',
      ...config.toJson(),
    });
  }

  @override
  Future<void> removeSmtpCredential() async {
    // remove_smtp_password() is service_role-only; the Edge Function checks
    // that the caller is an active administrator before calling it.
    await _invoke({'action': 'remove'});
  }

  @override
  Future<void> testSmtpConnection({
    required String host,
    required int port,
    required bool secure,
    required String username,
    required String password,
  }) async {
    await _invoke({
      'action': 'test',
      'host': host,
      'port': port,
      'secure': secure,
      'username': username,
      'password': password,
    });
  }

  @override
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
    await _invoke({
      'action': 'send_test',
      'confirm': confirm,
      'host': host,
      'port': port,
      'secure': secure,
      'username': username,
      'password': password,
      'sender_name': ?senderName,
      'sender_email': senderEmail,
      'recipient': recipient,
    });
  }
}