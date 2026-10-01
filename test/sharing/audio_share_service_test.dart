import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:ya_recorder/sharing/audio_share_service.dart';
import 'package:ya_recorder/storage/models/recording.dart';

void main() {
  test(
    'shares the completed M4A under its recording title without changing metadata',
    () async {
      final platform = _FakeAudioSharePlatform();
      final service = AudioShareService(platform: platform);
      final recording = Recording(
        id: 'recording-1',
        title: '项目讨论',
        filePath: '/private/recording-1.m4a',
        createdAt: DateTime.utc(2026, 10, 1),
        duration: const Duration(minutes: 1),
        fileSizeBytes: 1024,
      );

      await service.shareRecording(recording);

      expect(platform.filePath, recording.filePath);
      expect(platform.fileName, '项目讨论.m4a');
      expect(platform.title, recording.title);
      expect(recording.filePath, '/private/recording-1.m4a');
      expect(recording.title, '项目讨论');
    },
  );

  test('stages a title-named copy and removes it after sharing', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'ya-recorder-sharing-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final sourceFile = File(path.join(temporaryDirectory.path, 'internal.m4a'));
    await sourceFile.writeAsBytes([1, 2, 3]);
    final platform = SharePlusAudioSharePlatform(
      temporaryDirectoryProvider: () async => temporaryDirectory,
      share: (params) async {
        final stagedFile = File(params.files!.single.path);
        expect(path.basename(stagedFile.path), '项目讨论.m4a');
        expect(await stagedFile.readAsBytes(), [1, 2, 3]);
        return ShareResult.unavailable;
      },
    );

    await platform.shareM4a(
      filePath: sourceFile.path,
      fileName: '项目讨论.m4a',
      title: '项目讨论',
    );

    expect(await sourceFile.readAsBytes(), [1, 2, 3]);
    expect(
      await temporaryDirectory
          .list()
          .where((entity) => entity is Directory)
          .isEmpty,
      isTrue,
    );
  });
}

class _FakeAudioSharePlatform implements AudioSharePlatform {
  String? filePath;
  String? fileName;
  String? title;

  @override
  Future<void> shareM4a({
    required String filePath,
    required String fileName,
    required String title,
  }) async {
    this.filePath = filePath;
    this.fileName = fileName;
    this.title = title;
  }
}
