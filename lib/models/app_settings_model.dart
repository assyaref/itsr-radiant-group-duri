import 'package:json_annotation/json_annotation.dart';

part 'app_settings_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class AppSettingsModel {
  final String? itSupportGroupEmail;
  final String? managerEmail;
  final bool notificationsEnabled;
  final String? appBaseUrl;
  final DateTime? updatedAt;
  // SMTP configuration (non-secret fields)
  final String? smtpHost;
  final int? smtpPort;
  final bool? smtpSecure;
  final String? smtpUsername;
  final String? smtpSenderName;
  final String? smtpSenderEmail;
  final bool? passwordConfigured;
  final DateTime? smtpConfiguredAt;
  final DateTime? smtpLastTestAt;
  final String? smtpLastTestResult;
  final String? smtpLastTestError;
  final DateTime? smtpLastSuccessfulEmailAt;
  final DateTime? smtpLastFailedEmailAt;

  const AppSettingsModel({
    this.itSupportGroupEmail,
    this.managerEmail,
    required this.notificationsEnabled,
    this.appBaseUrl,
    this.updatedAt,
    this.smtpHost,
    this.smtpPort,
    this.smtpSecure,
    this.smtpUsername,
    this.smtpSenderName,
    this.smtpSenderEmail,
    this.passwordConfigured,
    this.smtpConfiguredAt,
    this.smtpLastTestAt,
    this.smtpLastTestResult,
    this.smtpLastTestError,
    this.smtpLastSuccessfulEmailAt,
    this.smtpLastFailedEmailAt,
  });

  factory AppSettingsModel.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsModelFromJson(json);
}
