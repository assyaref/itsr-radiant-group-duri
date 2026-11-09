// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'smtp_config_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SmtpConfigModel _$SmtpConfigModelFromJson(Map<String, dynamic> json) =>
    SmtpConfigModel(
      smtpHost: json['smtp_host'] as String?,
      smtpPort: (json['smtp_port'] as num?)?.toInt(),
      smtpSecure: json['smtp_secure'] as bool?,
      smtpUsername: json['smtp_username'] as String?,
      smtpSenderName: json['smtp_sender_name'] as String?,
      smtpSenderEmail: json['smtp_sender_email'] as String?,
      passwordConfigured: json['password_configured'] as bool,
      notificationsEnabled: json['notifications_enabled'] as bool,
      itSupportGroupEmail: json['it_support_group_email'] as String?,
      managerEmail: json['manager_email'] as String?,
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

Map<String, dynamic> _$SmtpConfigModelToJson(SmtpConfigModel instance) =>
    <String, dynamic>{
      'smtp_host': instance.smtpHost,
      'smtp_port': instance.smtpPort,
      'smtp_secure': instance.smtpSecure,
      'smtp_username': instance.smtpUsername,
      'smtp_sender_name': instance.smtpSenderName,
      'smtp_sender_email': instance.smtpSenderEmail,
      'password_configured': instance.passwordConfigured,
      'notifications_enabled': instance.notificationsEnabled,
      'it_support_group_email': instance.itSupportGroupEmail,
      'manager_email': instance.managerEmail,
      'smtp_configured_at': instance.smtpConfiguredAt?.toIso8601String(),
      'smtp_last_test_at': instance.smtpLastTestAt?.toIso8601String(),
      'smtp_last_test_result': instance.smtpLastTestResult,
      'smtp_last_test_error': instance.smtpLastTestError,
      'smtp_last_successful_email_at': instance.smtpLastSuccessfulEmailAt
          ?.toIso8601String(),
      'smtp_last_failed_email_at': instance.smtpLastFailedEmailAt
          ?.toIso8601String(),
    };
