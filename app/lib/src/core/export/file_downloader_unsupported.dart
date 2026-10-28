/// Fallback for platforms without a known download channel.
void downloadTextFile(String filename, String content) {
  throw UnsupportedError(
      'Text file download is not supported on this platform: $filename');
}
