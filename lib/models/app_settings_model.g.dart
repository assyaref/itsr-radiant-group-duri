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
    );
