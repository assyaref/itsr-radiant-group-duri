import 'package:flutter_test/flutter_test.dart';
import 'package:itsr_radiant/data/attachment_repository.dart';
import 'package:itsr_radiant/models/attachment_model.dart';

void main() {
  test('AttachmentModel parses the ticket_attachments row shape', () {
    // Columns of public.ticket_attachments (migration 20261112000100) plus the
    // embedded uploader name — the same shape the `attachments` function
    // returns after an upload (without `uploader`).
    final a = AttachmentModel.fromJson({
      'id': 'a1',
      'ticket_id': 't1',
      'uploaded_by': 'u1',
      'file_name': 'foto.png',
      'mime_type': 'image/png',
      'size_bytes': 2048,
      'created_at': '2026-11-18T03:00:00Z',
      'uploader': {'full_name': 'Syarif'},
    });
    expect(a.fileSize, 2048);
    expect(a.displaySize, '2 KB');
    expect(a.uploaderName, 'Syarif');
    expect(a.isImage, isTrue);

    final b = AttachmentModel.fromJson({
      'id': 'a2',
      'ticket_id': 't1',
      'uploaded_by': null,
      'file_name': 'x.pdf',
      'mime_type': 'application/pdf',
      'size_bytes': 70,
      'created_at': '2026-11-18T03:00:00Z',
    });
    expect(b.uploadedBy, isNull);
    expect(b.uploaderName, isNull);
    expect(b.displaySize, '70 B');
  });

  test('only JPG, PNG and PDF are accepted client-side (matches backend)', () {
    expect('image/png'.isAllowedAttachmentMime, isTrue);
    expect('IMAGE/JPEG'.isAllowedAttachmentMime, isTrue);
    expect('application/pdf'.isAllowedAttachmentMime, isTrue);
    expect('application/zip'.isAllowedAttachmentMime, isFalse);
    expect('text/plain'.isAllowedAttachmentMime, isFalse);
  });
}
