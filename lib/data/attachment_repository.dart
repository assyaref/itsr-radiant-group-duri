import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/attachment_model.dart';

/// Limits enforced client-side before any call to Supabase Storage.
const int kMaxAttachmentSize = 10 * 1024 * 1024; // 10 MiB

/// MIME types allowed for ticket attachments.
const Set<String> kAllowedAttachmentMimeTypes = {
  'application/pdf',
  'image/png',
  'image/jpeg',
  'image/jpg',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'text/plain',
  'application/zip',
};

extension StringMimeValidation on String {
  bool get isAllowedAttachmentMime => kAllowedAttachmentMimeTypes.contains(
        toLowerCase().trim(),
      );
}

abstract class AttachmentRepository {
  /// Upload a file to Supabase Storage and create a metadata row.
  /// Returns the created [AttachmentModel].
  Future<AttachmentModel> uploadAttachment({
    required String ticketId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    required String uploadedBy,
  });

  /// List attachments for a ticket (metadata only).
  Future<List<AttachmentModel>> listAttachments(String ticketId);

  /// Get a time-limited signed URL for downloading an attachment.
  /// Returns null if the caller cannot see the attachment.
  Future<String?> getDownloadUrl(String attachmentId, {int expiresIn = 300});

  /// Delete an attachment (staff/administrator only). Removes both the
  /// Storage object and the metadata row.
  Future<void> deleteAttachment(String attachmentId);
}

class SupabaseAttachmentRepository implements AttachmentRepository {
  SupabaseAttachmentRepository(this._client);
  final SupabaseClient _client;

  static const _bucket = 'ticket-attachments';

  @override
  Future<AttachmentModel> uploadAttachment({
    required String ticketId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    required String uploadedBy,
  }) async {
    if (bytes.length > kMaxAttachmentSize) {
      throw ArgumentError(
        'File too large: ${bytes.length} bytes (max $kMaxAttachmentSize)',
      );
    }
    if (!mimeType.isAllowedAttachmentMime) {
      throw ArgumentError('MIME type not allowed: $mimeType');
    }

    final safeName = fileName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath = 'tickets/$ticketId/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    // Upload to Storage first (anon key; bucket policies enforce access).
    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    // Create metadata row (table RLS further restricts by ticket visibility).
    final row = await _client
        .from('ticket_attachments')
        .insert({
          'ticket_id': ticketId,
          'storage_path': storagePath,
          'file_name': safeName,
          'mime_type': mimeType,
          'file_size': bytes.length,
          'uploaded_by': uploadedBy,
        })
        .select()
        .single();

    return AttachmentModel.fromJson(Map<String, dynamic>.from(row));
  }

  @override
  Future<List<AttachmentModel>> listAttachments(String ticketId) async {
    final rows = await _client
        .from('ticket_attachments')
        .select('*, uploader:profiles(full_name)')
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: false);
    return rows.map((r) => AttachmentModel.fromJson(Map<String, dynamic>.from(r))).toList();
  }

  @override
  Future<String?> getDownloadUrl(String attachmentId, {int expiresIn = 300}) async {
    final row = await _client
        .from('ticket_attachments')
        .select('storage_path')
        .eq('id', attachmentId)
        .maybeSingle();
    if (row == null) return null;
    final path = row['storage_path'] as String;
    return _client.storage.from(_bucket).createSignedUrl(path, expiresIn);
  }

  @override
  Future<void> deleteAttachment(String attachmentId) async {
    final row = await _client
        .from('ticket_attachments')
        .select('storage_path')
        .eq('id', attachmentId)
        .maybeSingle();
    if (row == null) return;
    await _client.storage.from(_bucket).remove([row['storage_path'] as String]);
    await _client.from('ticket_attachments').delete().eq('id', attachmentId);
  }
}
