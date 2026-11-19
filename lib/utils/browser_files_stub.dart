import 'dart:typed_data';

import 'browser_files_types.dart';
export 'browser_files_types.dart';

/// Test / non-web stand-ins. Tests can inject files via [debugPickedFiles].
List<PickedFile>? debugPickedFiles;
final List<String> debugDownloads = [];

Future<void> downloadBytes(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  debugDownloads.add(filename);
}

Future<List<PickedFile>> pickFiles({
  String accept = '',
  bool multiple = true,
}) async => debugPickedFiles ?? const [];

/// Non-web stand-in: pasting files is a browser feature. Returns a no-op
/// cancel function.
void Function() listenForPastedFiles(
  void Function(PickedFile file) onFile, {
  void Function(String mimeType)? onUnsupported,
  Set<String> allowedMimeTypes = const {'image/png', 'image/jpeg'},
}) => () {};
