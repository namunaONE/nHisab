import 'package:web/web.dart' as web;

/// Browser download via an anchor pointing at a data URL.
void downloadTextFile(String filename, String content) {
  final uri = 'data:text/plain;charset=utf-8,${Uri.encodeFull(content)}';
  web.HTMLAnchorElement()
    ..href = uri
    ..download = filename
    ..click();
}
