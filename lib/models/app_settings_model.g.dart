// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppSettingsModel _$AppSettingsModelFromJson(Map<String, dynamic> json) =>
    AppSettingsModel(
      itSupportGroupEmail: json['it_support_group_email'] as String?,
      managerEmail: json['manager_email'] as String?,
      notificationsEnabled: json['notifications_enabled'] as bool,
      appBaseUrl: json['app_base_url'] as String?,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      smtpHost: json['smtp_host'] as String?,
      smtpPort: (json['smtp_port'] as num?)?.toInt(),
      smtpSecure: json['smtp_secure'] as bool?,
      smtpUsername: json['smtp_username'] as String?,
      smtpSenderName: json['smtp_sender_name'] as String?,
      smtpSenderEmail: json['smtp_sender_email'] as String?,
      passwordConfigured: json['password_configured'] as bool?,
      smtpConfiguredAt: json['smtp_configured_at'] == null
          ? null
          : DateTime.parse(json['smtp_configured_at'] as String),
      smtpLastTestAt: json['smtp_last_test_at'] == null
          ? null
          : DateTime.parse(json['smtp_last_test_at'] as String),
      smtpLastTestResult: json['smtp_last_test_result'] as String?,
      smtpLastTestError: json['smtp_last_test_error'] as String?,
      smtpLastSuccessfulEmailAt: json['smtp_last_successful_email_at'] == null
          ? null
          : DateTime.parse(json['smtp_last_successful_email_at'] as String),
      smtpLastFailedEmailAt: json['smtp_last_failed_email_at'] == null
          ? null
          : DateTime.parse(json['smtp_last_failed_email_at'] as String),
    );
