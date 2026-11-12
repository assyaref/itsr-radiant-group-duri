/// Download bytes as a file / pick local files, in the browser.
/// On non-web platforms (unit tests) these are no-ops.
library;

export 'browser_files_stub.dart'
    if (dart.library.js_interop) 'browser_files_web.dart';
