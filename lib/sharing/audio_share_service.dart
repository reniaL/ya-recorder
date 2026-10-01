import 'package:share_plus/share_plus.dart';

import '../storage/models/recording.dart';

abstract interface class AudioSharePlatform {
  Future<void> shareM4a({
    required String filePath,
    required String fileName,
    required String title,
  });
}

class SharePlusAudioSharePlatform implements AudioSharePlatform {
  const SharePlusAudioSharePlatform();

  @override
  Future<void> shareM4a({
    required String filePath,
    required String fileName,
    required String title,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        title: title,
        subject: title,
        files: [XFile(filePath, mimeType: 'audio/mp4')],
        fileNameOverrides: [fileName],
      ),
    );
  }
}

class AudioShareService {
  AudioShareService({AudioSharePlatform? platform})
    : _platform = platform ?? const SharePlusAudioSharePlatform();

  final AudioSharePlatform _platform;

  Future<void> shareRecording(Recording recording) {
    return _platform.shareM4a(
      filePath: recording.filePath,
      fileName: _sharedFileName(recording.title),
      title: recording.title,
    );
  }

  static String _sharedFileName(String title) {
    final sanitizedTitle = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .trim();
    final baseName = sanitizedTitle.isEmpty ? '录音' : sanitizedTitle;
    return baseName.toLowerCase().endsWith('.m4a') ? baseName : '$baseName.m4a';
  }
}
