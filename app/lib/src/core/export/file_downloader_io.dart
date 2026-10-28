import 'dart:io';

/// Writes the file to the system temp directory (desktop/mobile/tests).
void downloadTextFile(String filename, String content) {
  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}$filename';
  File(path).writeAsStringSync(content);
  stderr.writeln('File saved to: $path');
}
