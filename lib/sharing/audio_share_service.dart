import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../storage/models/recording.dart';

typedef TemporaryDirectoryProvider = Future<Directory> Function();
typedef ShareInvoker = Future<ShareResult> Function(ShareParams params);

abstract interface class AudioSharePlatform {
  Future<void> shareM4a({
    required String filePath,
    required String fileName,
    required String title,
  });
}

class SharePlusAudioSharePlatform implements AudioSharePlatform {
  SharePlusAudioSharePlatform({
    TemporaryDirectoryProvider? temporaryDirectoryProvider,
    ShareInvoker? share,
  }) : _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory,
       _share = share ?? SharePlus.instance.share;

  final TemporaryDirectoryProvider _temporaryDirectoryProvider;
  final ShareInvoker _share;

  @override
  Future<void> shareM4a({
    required String filePath,
    required String fileName,
    required String title,
  }) async {
    final temporaryDirectory = await _temporaryDirectoryProvider();
    final stagingDirectory = await temporaryDirectory.createTemp(
      'recording-share-',
    );
    final stagedFile = File(path.join(stagingDirectory.path, fileName));

    try {
      await File(filePath).copy(stagedFile.path);
      await _share(
        ShareParams(
          title: title,
          subject: title,
          files: [XFile(stagedFile.path, mimeType: 'audio/mp4')],
        ),
      );
    } finally {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }
    }
  }
}

class AudioShareService {
  AudioShareService({AudioSharePlatform? platform})
    : _platform = platform ?? SharePlusAudioSharePlatform();

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
