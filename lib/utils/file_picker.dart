import 'dart:typed_data';

import 'browser_files.dart';

/// Picks a single PDF/PNG/JPEG file. Returns null if cancelled.
/// Built on [pickFiles] (package:web), so it has no `dart:html` dependency
/// and is a no-op stand-in outside the browser (tests).
Future<(String fileName, String mimeType, Uint8List bytes)?> pickFile({
  Set<String>? allowedExtensions,
}) async {
  final files = await pickFiles(
    accept: (allowedExtensions ?? const {'.pdf', '.png', '.jpg', '.jpeg'}).join(
      ',',
    ),
    multiple: false,
  );
  if (files.isEmpty) return null;
  final f = files.first;
  return (
    f.name,
    f.mimeType.isNotEmpty ? f.mimeType : 'application/octet-stream',
    f.bytes,
  );
}
