import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'browser_files_types.dart';
export 'browser_files_types.dart';

List<PickedFile>? debugPickedFiles;
final List<String> debugDownloads = [];

/// Saves [bytes] through a temporary object URL + <a download>.
Future<void> downloadBytes(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  // Give the browser time to start the download before revoking.
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}

/// Opens the browser file chooser and reads the chosen files.
/// Returns an empty list when the user cancels.
Future<List<PickedFile>> pickFiles({
  String accept = '',
  bool multiple = true,
}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept
    ..multiple = multiple
    ..style.display = 'none';
  web.document.body?.append(input);
  final done = Completer<List<PickedFile>>();

  input.addEventListener(
    'change',
    (web.Event _) {
      final files = input.files;
      if (files == null || files.length == 0) {
        if (!done.isCompleted) done.complete(const []);
        return;
      }
      final reads = <Future<PickedFile>>[];
      for (var i = 0; i < files.length; i++) {
        final f = files.item(i)!;
        reads.add(
          f.arrayBuffer().toDart.then(
            (buf) => PickedFile(
              name: f.name,
              bytes: buf.toDart.asUint8List(),
              mimeType: f.type.isEmpty ? 'application/octet-stream' : f.type,
            ),
          ),
        );
      }
      Future.wait(reads).then(
        (v) {
          if (!done.isCompleted) done.complete(v);
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
      );
    }.toJS,
  );
  input.addEventListener(
    'cancel',
    (web.Event _) {
      if (!done.isCompleted) done.complete(const []);
    }.toJS,
  );
  input.click();
  try {
    return await done.future;
  } finally {
    input.remove();
  }
}
