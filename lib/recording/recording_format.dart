/// Stable values shared by the platform protocol and the recording index.
enum RecordingFormat {
  m4a('m4a', 'audio/mp4'),
  mp3('mp3', 'audio/mpeg');

  const RecordingFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
  String get wireName => extension;
  String get label => extension.toUpperCase();

  static RecordingFormat fromWireValue(Object? value) {
    for (final format in values) {
      if (value == format.wireName) return format;
    }
    throw FormatException('Unsupported recording format: $value');
  }

  bool matchesCompletedPath(String filePath) =>
      filePath.toLowerCase().endsWith('.$extension');
}
