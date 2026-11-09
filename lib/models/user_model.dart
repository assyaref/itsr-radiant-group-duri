import 'package:json_annotation/json_annotation.dart';

part 'user_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class UserModel {
  final String id;
  final String employeeNumber;
  final String email;
  final String fullName;
  @JsonKey(defaultValue: 'General')
  final String department;
  final String role;
  final String? phoneNumber;
  @JsonKey(defaultValue: true)
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserModel({
    required this.id,
    required this.employeeNumber,
    required this.email,
    required this.fullName,
    required this.department,
    required this.role,
    this.phoneNumber,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isStaff => role == 'it_support' || role == 'administrator';
  bool get isAdmin => role == 'administrator';

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);
  Map<String, dynamic> toJson() => _$UserModelToJson(this);
}
