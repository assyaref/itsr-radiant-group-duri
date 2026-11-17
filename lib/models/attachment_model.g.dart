// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attachment_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AttachmentModel _$AttachmentModelFromJson(Map<String, dynamic> json) =>
    AttachmentModel(
      id: json['id'] as String,
      ticketId: json['ticket_id'] as String,
      storagePath: json['storage_path'] as String,
      fileName: json['file_name'] as String,
      mimeType: json['mime_type'] as String,
      fileSize: (json['file_size'] as num).toInt(),
      uploadedBy: json['uploaded_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      uploaderName: json['uploader_name'] as String?,
    );

Map<String, dynamic> _$AttachmentModelToJson(AttachmentModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'ticket_id': instance.ticketId,
      'storage_path': instance.storagePath,
      'file_name': instance.fileName,
      'mime_type': instance.mimeType,
      'file_size': instance.fileSize,
      'uploaded_by': instance.uploadedBy,
      'created_at': instance.createdAt.toIso8601String(),
      'uploader_name': instance.uploaderName,
    };
