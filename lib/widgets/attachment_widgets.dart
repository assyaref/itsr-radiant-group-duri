import 'package:flutter/material.dart';

import '../models/attachment_model.dart';
import '../utils/browser_files.dart';
import '../utils/formatters.dart';
import 'common.dart';
import 'employee_ui.dart';

/// Opens the file chooser and returns the valid files; shows a message for
/// files that were rejected (type / size / count).
Future<List<PickedFile>> pickAttachmentFiles(
  BuildContext context, {
  required int alreadyChosen,
}) async {
  final picked = await pickFiles(accept: AttachmentModel.accept);
  final ok = <PickedFile>[];
  final errors = <String>[];
  for (final f in picked) {
    final err = AttachmentModel.validate(f.name, f.size);
    if (err != null) {
      errors.add(err);
    } else if (alreadyChosen + ok.length >= AttachmentModel.maxPerTicket) {
      errors.add('Maksimal ${AttachmentModel.maxPerTicket} lampiran per tiket');
      break;
    } else {
      ok.add(f);
    }
  }
  if (errors.isNotEmpty && context.mounted) {
    showSnack(context, errors.join('\n'), error: true);
  }
  return ok;
}

/// "5. Form Buat Tiket (Langkah 2)": upload box, thumbnails, file list.
class AttachmentPicker extends StatelessWidget {
  const AttachmentPicker({
    super.key,
    required this.files,
    required this.onAdd,
    required this.onRemove,
    this.enabled = true,
  });

  final List<PickedFile> files;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final images = [
      for (var i = 0; i < files.length; i++)
        if (files[i].mimeType.startsWith('image/')) i,
    ];
    final canAdd = enabled && files.length < AttachmentModel.maxPerTicket;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFFF8FAFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFBFD4FE), width: 1.4),
          ),
          child: InkWell(
            key: const Key('attachment_pick_area'),
            borderRadius: BorderRadius.circular(14),
            onTap: canAdd ? onAdd : null,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              child: Column(
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 44,
                    color: EColors.blue,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Ketuk untuk upload foto atau file',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: EColors.text),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Format: JPG, PNG, PDF (Maks. 10 MB)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: EColors.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (images.isNotEmpty) ...[
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final size = (c.maxWidth - 2 * 10) / 3;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final i in images)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        files[i].bytes,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        semanticLabel: files[i].name,
                        errorBuilder: (_, _, _) => Container(
                          width: size,
                          height: size,
                          color: const Color(0xFFF1F5F9),
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: EColors.grey,
                          ),
                        ),
                      ),
                    ),
                  if (canAdd)
                    Material(
                      color: EColors.blueSoft,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: onAdd,
                        child: SizedBox(
                          width: size,
                          height: size,
                          child: const Icon(
                            Icons.add,
                            color: EColors.blue,
                            size: 30,
                            semanticLabel: 'Tambah lampiran',
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 12),
        for (var i = 0; i < files.length; i++) ...[
          ECard(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            child: Row(
              children: [
                Icon(
                  files[i].mimeType == 'application/pdf'
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined,
                  color: EColors.text,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        files[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: EColors.ink,
                        ),
                      ),
                      Text(
                        AttachmentModel.formatSize(files[i].size),
                        style: const TextStyle(
                          fontSize: 12,
                          color: EColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Hapus ${files[i].name}',
                  onPressed: enabled ? () => onRemove(i) : null,
                  icon: const Icon(Icons.close, color: EColors.text),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: EColors.blueSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_rounded, color: EColors.blue, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Lampiran membantu tim IT memahami masalah Anda lebih cepat.',
                  style: TextStyle(
                    color: EColors.blueDark,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One stored attachment with a download button ("9. Detail Tiket (Tab Lampiran)").
class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.onDownload,
    this.busy = false,
  });
  final AttachmentModel attachment;
  final VoidCallback onDownload;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    return ECard(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: (a.isImage ? EColors.blue : EColors.red).withValues(
                alpha: 0.1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              a.isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined,
              color: a.isImage ? EColors.blue : EColors.red,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: EColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${AttachmentModel.formatSize(a.sizeBytes)} · ${Fmt.dateTime(a.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: EColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('download_${a.id}'),
            tooltip: 'Unduh ${a.fileName}',
            onPressed: busy ? null : onDownload,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded, color: EColors.text),
          ),
        ],
      ),
    );
  }
}
