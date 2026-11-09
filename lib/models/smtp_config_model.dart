import 'package:json_annotation/json_annotation.dart';

part 'smtp_config_model.g.dart';

/// SMTP configuration as returned by the /smtp-config Edge Function.
/// The SMTP password is NEVER included in this model — it is stored in
/// Vault and never sent back to the client.
@JsonSerializable(fieldRename: FieldRename.snake)
class SmtpConfigModel {
  final String? smtpHost;
  final int? smtpPort;
  final bool? smtpSecure;
  final String? smtpUsername;
  final String? smtpSenderName;
  final String? smtpSenderEmail;
  final bool passwordConfigured;
  final bool notificationsEnabled;
  final String? itSupportGroupEmail;
  final String? managerEmail;
  final DateTime? smtpConfiguredAt;
  final DateTime? smtpLastTestAt;
  final String? smtpLastTestResult;
  final String? smtpLastTestError;
  final DateTime? smtpLastSuccessfulEmailAt;
  final DateTime? smtpLastFailedEmailAt;

  const SmtpConfigModel({
    this.smtpHost,
    this.smtpPort,
    this.smtpSecure,
    this.smtpUsername,
    this.smtpSenderName,
    this.smtpSenderEmail,
    required this.passwordConfigured,
    required this.notificationsEnabled,
    this.itSupportGroupEmail,
    this.managerEmail,
    this.smtpConfiguredAt,
    this.smtpLastTestAt,
    this.smtpLastTestResult,
    this.smtpLastTestError,
    this.smtpLastSuccessfulEmailAt,
    this.smtpLastFailedEmailAt,
  });

  bool get isConfigured =>
      smtpHost != null &&
      smtpPort != null &&
      smtpUsername != null &&
      smtpSenderEmail != null &&
      passwordConfigured;

  factory SmtpConfigModel.fromJson(Map<String, dynamic> json) =>
      _$SmtpConfigModelFromJson(json);

  Map<String, dynamic> toJson() => _$SmtpConfigModelToJson(this);
}

/// Input payload for saving SMTP configuration via the Edge Function.
/// The password is included here but is never stored client-side after
/// the save call completes.
class SmtpConfigInput {
  final String host;
  final int port;
  final bool secure; // true = SSL/TLS (port 465), false = STARTTLS (port 587)
  final String username;
  final String password;
  final String? senderName;
  final String senderEmail;

  const SmtpConfigInput({
    required this.host,
    required this.port,
    required this.secure,
    required this.username,
    required this.password,
    this.senderName,
    required this.senderEmail,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'secure': secure,
        'username': username,
        'password': password,
        'sender_name': senderName,
        'sender_email': senderEmail,
      };
}