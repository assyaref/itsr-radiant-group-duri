import 'package:json_annotation/json_annotation.dart';

part 'app_settings_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class AppSettingsModel {
  final String? itSupportGroupEmail;
  final String? managerEmail;
  final bool notificationsEnabled;
  final String? appBaseUrl;
  final DateTime? updatedAt;

  const AppSettingsModel({
    this.itSupportGroupEmail,
    this.managerEmail,
    required this.notificationsEnabled,
    this.appBaseUrl,
    this.updatedAt,
  });

  factory AppSettingsModel.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsModelFromJson(json);
}
