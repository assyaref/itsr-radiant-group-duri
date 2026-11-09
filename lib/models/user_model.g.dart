// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserModel _$UserModelFromJson(Map<String, dynamic> json) => UserModel(
  id: json['id'] as String,
  employeeNumber: json['employee_number'] as String,
  email: json['email'] as String,
  fullName: json['full_name'] as String,
  department: json['department'] as String? ?? 'General',
  role: json['role'] as String,
  phoneNumber: json['phone_number'] as String?,
  isActive: json['is_active'] as bool? ?? true,
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$UserModelToJson(UserModel instance) => <String, dynamic>{
  'id': instance.id,
  'employee_number': instance.employeeNumber,
  'email': instance.email,
  'full_name': instance.fullName,
  'department': instance.department,
  'role': instance.role,
  'phone_number': instance.phoneNumber,
  'is_active': instance.isActive,
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
};
