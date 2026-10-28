/// Platform-conditional file download barrel.
///
/// Exports `downloadTextFile(filename, content)` implemented for the current
/// platform so Flutter web-only libraries (`package:web`, `dart:html`,
/// `dart:js_interop`) never enter the VM (test/mobile) compile graph.
library;

export 'file_downloader_unsupported.dart'
    if (dart.library.html) 'file_downloader_web.dart'
    if (dart.library.io) 'file_downloader_io.dart';
