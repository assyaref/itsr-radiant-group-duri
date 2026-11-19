import 'package:web/web.dart' as web;

/// Opens [url] in a new tab with `rel="noopener noreferrer"` semantics
/// (window features `noopener,noreferrer`), mirroring a plain
/// `<a target="_blank" rel="noopener noreferrer">`.
void openExternalLink(String url) {
  web.window.open(url, '_blank', 'noopener,noreferrer');
}
