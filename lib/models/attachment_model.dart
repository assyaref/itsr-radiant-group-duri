/// Metadata of a ticket attachment (the file itself is in Google Drive).
class AttachmentModel {
  const AttachmentModel({
    required this.id,
    required this.ticketId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    this.uploadedBy,
  });

  final String id;
  final String ticketId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;
  final String? uploadedBy;

  bool get isImage => mimeType.startsWith('image/');

  factory AttachmentModel.fromJson(Map<String, dynamic> j) => AttachmentModel(
    id: j['id'] as String,
    ticketId: j['ticket_id'] as String,
    fileName: j['file_name'] as String,
    mimeType: j['mime_type'] as String,
    sizeBytes: (j['size_bytes'] as num).toInt(),
    createdAt: DateTime.parse(j['created_at'] as String),
    uploadedBy: j['uploaded_by'] as String?,
  );

  /// "2.4 MB", "820 KB".
  static String formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).ceil()} KB';
  }

  static const maxBytes = 10 * 1024 * 1024;
  static const maxPerTicket = 10;
  static const accept =
      '.jpg,.jpeg,.png,.pdf,image/jpeg,image/png,application/pdf';

  /// Client-side pre-check (the server re-checks the real file content).
  static String? validate(String name, int size) {
    final n = name.toLowerCase();
    final okType =
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.pdf');
    if (!okType) return '$name: hanya JPG, PNG, atau PDF';
    if (size > maxBytes) return '$name: lebih dari 10 MB';
    if (size == 0) return '$name: file kosong';
    return null;
  }
}
