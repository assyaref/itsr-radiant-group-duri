import 'dart:typed_data';

/// Picks a single file. Not supported on non-web platforms.
Future<(String fileName, String mimeType, Uint8List bytes)?> pickFile({
  Set<String>? allowedExtensions,
}) async => null;
