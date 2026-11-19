/// Test / non-web stand-in for [openExternalLink].
final List<String> debugOpenedLinks = [];

void openExternalLink(String url) {
  debugOpenedLinks.add(url);
}
