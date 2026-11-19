/// Opens [url] in a new browser tab.
/// Outside the browser (tests) this records the link in [debugOpenedLinks].
library;

export 'open_link_stub.dart' if (dart.library.js_interop) 'open_link_web.dart';
