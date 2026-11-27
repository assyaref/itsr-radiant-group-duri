import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/attachment_repository.dart';
import '../models/attachment_model.dart';
import 'auth_provider.dart';

/// Provider for the attachment repository.
final attachmentRepositoryProvider = Provider<AttachmentRepository>((ref) {
  return SupabaseAttachmentRepository(ref.watch(supabaseProvider));
});

/// Notifier for the list of attachments on a ticket.
class AttachmentsNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<AttachmentModel>, String> {
  @override
  Future<List<AttachmentModel>> build(String ticketId) async {
    return ref.read(attachmentRepositoryProvider).listAttachments(ticketId);
  }
}

final attachmentsProvider = AsyncNotifierProvider.autoDispose
    .family<AttachmentsNotifier, List<AttachmentModel>, String>(
      AttachmentsNotifier.new,
    );

class AttachmentActions {
  AttachmentActions(this._ref);
  final Ref _ref;

  Future<AttachmentModel> uploadAttachment({
    required String ticketId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    required String uploadedBy,
    bool notify = false,
  }) async {
    final result = await _ref
        .read(attachmentRepositoryProvider)
        .uploadAttachment(
          ticketId: ticketId,
          fileName: fileName,
          mimeType: mimeType,
          bytes: bytes,
          uploadedBy: uploadedBy,
          notify: notify,
        );
    _ref.invalidate(attachmentsProvider(ticketId));
    // Send the queued email now (chat file without text); otherwise the
    // scheduler picks it up.
    if (notify) _ref.read(ticketRepositoryProvider).kickNotifications();
    return result;
  }

  Future<Uint8List> downloadAttachment(String attachmentId) =>
      _ref.read(attachmentRepositoryProvider).downloadAttachment(attachmentId);

  Future<void> deleteAttachment(String ticketId, String attachmentId) async {
    await _ref.read(attachmentRepositoryProvider).deleteAttachment(attachmentId);
    _ref.invalidate(attachmentsProvider(ticketId));
    _ref.invalidate(attachmentBytesProvider(attachmentId));
  }
}

/// Bytes of one attachment (for inline image previews in the chat).
/// Cached for the session so scrolling does not download an image again.
final attachmentBytesProvider = FutureProvider.family<Uint8List, String>((
  ref,
  attachmentId,
) {
  return ref
      .read(attachmentRepositoryProvider)
      .downloadAttachment(attachmentId);
});

final attachmentActionsProvider = Provider<AttachmentActions>(
  (ref) => AttachmentActions(ref),
);
