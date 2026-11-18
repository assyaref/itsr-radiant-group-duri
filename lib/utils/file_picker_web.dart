import 'dart:async';
import 'dart:html';
import 'dart:typed_data';

/// Picks a single file via an HTML file input. Returns null if cancelled.
Future<(String fileName, String mimeType, Uint8List bytes)?> pickFile({
  Set<String>? allowedExtensions,
}) async {
  final input = FileUploadInputElement()
    ..accept = (allowedExtensions ?? const {
      '.pdf', '.png', '.jpg', '.jpeg'
    }).join(',')
    ..multiple = false;

  input.click();

  await input.onChange.first;

  final files = input.files;
  if (files == null || files.isEmpty) return null;

  final file = files.first;
  final reader = FileReader();
  final completer = Completer<(String, String, Uint8List)>();

  reader.onLoadEnd.listen((_) {
    final bytes = reader.result! as List<int>;
    completer.complete((file.name, file.type.isNotEmpty ? file.type : 'application/octet-stream',
        Uint8List.fromList(bytes)));
  });

  reader.readAsArrayBuffer(file);
  return completer.future;
}
