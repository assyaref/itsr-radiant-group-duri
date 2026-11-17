import 'package:json_annotation/json_annotation.dart';

part 'attachment_model.g.dart';

/// Metadata for a file attachment on a ticket.
///
/// The file bytes live in Supabase Storage (bucket `ticket-attachments`);
/// this table stores only metadata. The password is never involved.
@JsonSerializable(fieldRename: FieldRename.snake)
class AttachmentModel {
  final String id;
  final String ticketId;
  final String storagePath;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String uploadedBy;
  final DateTime createdAt;
  final String? uploaderName;

  const AttachmentModel({
    required this.id,
    required this.ticketId,
    required this.storagePath,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.uploadedBy,
    required this.createdAt,
    this.uploaderName,
  });

  factory AttachmentModel.fromJson(Map<String, dynamic> json) =>
      _$AttachmentModelFromJson(json);

  Map<String, dynamic> toJson() => _$AttachmentModelToJson(this);

  /// Human-readable file size (e.g. "1.2 MB", "450 KB").
  String get displaySize {
    final kb = fileSize / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }

  bool get isImage => mimeType.startsWith('image/');
}
