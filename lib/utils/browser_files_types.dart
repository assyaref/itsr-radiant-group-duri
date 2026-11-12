import 'dart:typed_data';

/// A file chosen by the user, fully read into memory.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });
  final String name;
  final Uint8List bytes;
  final String mimeType;
  int get size => bytes.length;
}
