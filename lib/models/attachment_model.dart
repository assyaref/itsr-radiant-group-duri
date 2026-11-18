/// Metadata for a file attachment on a ticket.
///
/// The file bytes live in a Google Drive folder managed by the `attachments`
/// Edge Function; `public.ticket_attachments` only stores metadata. Clients
/// never see the Drive file id — downloads are proxied by the function.
class AttachmentModel {
  final String id;
  final String ticketId;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String? uploadedBy;
  final DateTime createdAt;
  final String? uploaderName;

  const AttachmentModel({
    required this.id,
    required this.ticketId,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.uploadedBy,
    required this.createdAt,
    this.uploaderName,
  });

  factory AttachmentModel.fromJson(Map<String, dynamic> json) {
    final uploader = json['uploader'];
    return AttachmentModel(
      id: json['id'] as String,
      ticketId: json['ticket_id'] as String,
      fileName: json['file_name'] as String,
      mimeType: json['mime_type'] as String,
      fileSize: (json['size_bytes'] as num).toInt(),
      uploadedBy: json['uploaded_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      uploaderName: uploader is Map ? uploader['full_name'] as String? : null,
    );
  }

  /// Human-readable file size (e.g. "1.2 MB", "450 KB").
  String get displaySize {
    final kb = fileSize / 1024;
    if (kb < 1) return '$fileSize B';
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  bool get isImage => mimeType.startsWith('image/');
}
