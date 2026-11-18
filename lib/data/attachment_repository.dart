import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/attachment_model.dart';
import '../utils/error_messages.dart';

/// Limits checked client-side before upload. The `attachments` Edge Function
/// enforces the same rules server-side by sniffing the real file content.
const int kMaxAttachmentSize = 10 * 1024 * 1024; // 10 MiB

/// File types accepted by the backend: JPG, PNG and PDF only.
const Set<String> kAllowedAttachmentMimeTypes = {
  'application/pdf',
  'image/png',
  'image/jpeg',
  'image/jpg',
};

/// `accept` attribute for the browser file chooser.
const String kAttachmentAccept = '.jpg,.jpeg,.png,.pdf';

extension StringMimeValidation on String {
  bool get isAllowedAttachmentMime =>
      kAllowedAttachmentMimeTypes.contains(toLowerCase().trim());
}

abstract class AttachmentRepository {
  /// Uploads a file through the `attachments` Edge Function (stored in
  /// Google Drive) and returns the created metadata row.
  Future<AttachmentModel> uploadAttachment({
    required String ticketId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    required String uploadedBy,
  });

  /// Lists attachments for a ticket (metadata only, RLS-scoped).
  Future<List<AttachmentModel>> listAttachments(String ticketId);

  /// Downloads the file bytes (proxied by the Edge Function).
  Future<Uint8List> downloadAttachment(String attachmentId);
}

class SupabaseAttachmentRepository implements AttachmentRepository {
  SupabaseAttachmentRepository(this._client);
  final SupabaseClient _client;

  static const _function = 'attachments';
  static const _columns =
      'id, ticket_id, uploaded_by, file_name, mime_type, size_bytes, created_at, '
      'uploader:profiles(full_name)';

  @override
  Future<AttachmentModel> uploadAttachment({
    required String ticketId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    required String uploadedBy,
  }) async {
    if (bytes.length > kMaxAttachmentSize) {
      throw const AppFailure('File terlalu besar (maks 10 MB).');
    }
    if (!mimeType.isAllowedAttachmentMime) {
      throw const AppFailure('Tipe file tidak diizinkan (hanya JPG, PNG, PDF).');
    }
    final res = await _client.functions.invoke(
      _function,
      body: {
        'action': 'upload',
        'ticket_id': ticketId,
        'file_name': fileName,
        'data_base64': base64Encode(bytes),
      },
    );
    final data = res.data;
    if (data is! Map) throw StateError('Unexpected upload response');
    return AttachmentModel.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  Future<List<AttachmentModel>> listAttachments(String ticketId) async {
    final rows = await _client
        .from('ticket_attachments')
        .select(_columns)
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: false);
    return rows
        .map((r) => AttachmentModel.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  @override
  Future<Uint8List> downloadAttachment(String attachmentId) async {
    final res = await _client.functions.invoke(
      _function,
      body: {'action': 'download', 'attachment_id': attachmentId},
    );
    final data = res.data;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    throw StateError('Unexpected download response');
  }
}
