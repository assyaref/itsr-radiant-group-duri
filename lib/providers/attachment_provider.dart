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

final attachmentsProvider =
    AsyncNotifierProvider.autoDispose.family<AttachmentsNotifier, List<AttachmentModel>, String>(
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
  }) async {
    final result = await _ref.read(attachmentRepositoryProvider).uploadAttachment(
          ticketId: ticketId,
          fileName: fileName,
          mimeType: mimeType,
          bytes: bytes,
          uploadedBy: uploadedBy,
        );
    _ref.invalidate(attachmentsProvider(ticketId));
    return result;
  }

  Future<String?> getDownloadUrl(String attachmentId, {int expiresIn = 300}) async {
    return _ref.read(attachmentRepositoryProvider).getDownloadUrl(
          attachmentId,
          expiresIn: expiresIn,
        );
  }

  Future<void> deleteAttachment(String attachmentId, String ticketId) async {
    await _ref.read(attachmentRepositoryProvider).deleteAttachment(attachmentId);
    _ref.invalidate(attachmentsProvider(ticketId));
  }
}

final attachmentActionsProvider = Provider<AttachmentActions>((ref) => AttachmentActions(ref));
