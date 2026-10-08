import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/sharing/audio_share_service.dart';
import 'package:ya_recorder/storage/models/recording.dart';

void main() {
  test(
    'shares the completed M4A under its recording title without changing metadata',
    () async {
      final platform = _FakeAudioSharePlatform();
      final service = AudioShareService(platform: platform);
      final recording = Recording(
        format: RecordingFormat.m4a,
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

    await platform.shareAudio(
      filePath: sourceFile.path,
      fileName: '项目讨论.m4a',
      title: '项目讨论',
      format: RecordingFormat.m4a,
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

  test('MP3 shares with its own extension and MIME format', () async {
    final platform = _FakeAudioSharePlatform();
    final recording = Recording(
      id: 'mp3',
      title: 'MP3',
      filePath: '/private/mp3.mp3',
      format: RecordingFormat.mp3,
      createdAt: DateTime.utc(2026, 10, 7),
      duration: const Duration(seconds: 1),
      fileSizeBytes: 20,
    );
    await AudioShareService(platform: platform).shareRecording(recording);
    expect(platform.filePath, recording.filePath);
    expect(platform.fileName, 'MP3.mp3');
    expect(platform.format, RecordingFormat.mp3);
  });
  for (final format in RecordingFormat.values) {
    for (final result in ['success', 'dismissed', 'failure']) {
      test(
        '${format.label} stages correct MIME and cleans up on $result',
        () async {
          final directory = await Directory.systemTemp.createTemp('ya-share-');
          addTearDown(() => directory.delete(recursive: true));
          final source = File(
            path.join(directory.path, 'internal.${format.extension}'),
          );
          await source.writeAsBytes([4, 5, 6]);
          final platform = SharePlusAudioSharePlatform(
            temporaryDirectoryProvider: () async => directory,
            share: (params) async {
              expect(params.files!.single.mimeType, format.mimeType);
              expect(
                path.basename(params.files!.single.path),
                '标题.${format.extension}',
              );
              expect(params.title, '标题');
              expect(params.subject, '标题');
              expect(await File(params.files!.single.path).readAsBytes(), [
                4,
                5,
                6,
              ]);
              if (result == 'failure') throw StateError('Share failed');
              return ShareResult(
                '',
                result == 'success'
                    ? ShareResultStatus.success
                    : ShareResultStatus.dismissed,
              );
            },
          );
          final future = platform.shareAudio(
            filePath: source.path,
            fileName: '标题.${format.extension}',
            title: '标题',
            format: format,
          );
          if (result == 'failure') {
            await expectLater(future, throwsStateError);
          } else {
            await future;
          }
          expect(await source.readAsBytes(), [4, 5, 6]);
          expect(
            await directory.list().where((e) => e is Directory).isEmpty,
            isTrue,
          );
        },
      );
    }
  }

  test(
    'attachment title is sanitized and suffix follows recording format',
    () async {
      final platform = _FakeAudioSharePlatform();
      for (final entry in {
        '': '录音.mp3',
        '访谈/问题:*?': '访谈_问题___.mp3',
        '已命名.MP3': '已命名.MP3',
        '旧标题.m4a': '旧标题.m4a.mp3',
      }.entries) {
        await AudioShareService(platform: platform).shareRecording(
          Recording(
            id: 'name',
            title: entry.key,
            filePath: '/private/name.mp3',
            format: RecordingFormat.mp3,
            createdAt: DateTime.utc(2026),
            duration: const Duration(seconds: 1),
            fileSizeBytes: 1,
          ),
        );
        expect(platform.fileName, entry.value);
      }
    },
  );

  test('incomplete or mismatched paths never reach the share platform', () {
    final platform = _FakeAudioSharePlatform();
    for (final filePath in ['/private/one.mp3.part', '/private/one.m4a']) {
      final recording = Recording(
        id: 'one',
        title: '标题',
        filePath: filePath,
        format: RecordingFormat.mp3,
        createdAt: DateTime.utc(2026),
        duration: const Duration(seconds: 1),
        fileSizeBytes: 1,
      );
      expect(
        () => AudioShareService(platform: platform).shareRecording(recording),
        throwsStateError,
      );
    }
    expect(platform.filePath, isNull);
  });

  test('copy failure cleans staging directory and reports the error', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ya-share-missing-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final platform = SharePlusAudioSharePlatform(
      temporaryDirectoryProvider: () async => directory,
      share: (_) async => fail('Missing file must not invoke sharing'),
    );
    await expectLater(
      platform.shareAudio(
        filePath: path.join(directory.path, 'missing.mp3'),
        fileName: '标题.mp3',
        title: '标题',
        format: RecordingFormat.mp3,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await directory.list().isEmpty, isTrue);
  });
}

class _FakeAudioSharePlatform implements AudioSharePlatform {
  String? filePath;
  String? fileName;
  String? title;
  RecordingFormat? format;

  @override
  Future<void> shareAudio({
    required String filePath,
    required String fileName,
    required String title,
    required RecordingFormat format,
  }) async {
    this.filePath = filePath;
    this.fileName = fileName;
    this.title = title;
    this.format = format;
  }
}
