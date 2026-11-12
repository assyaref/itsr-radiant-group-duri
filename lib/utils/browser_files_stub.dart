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
