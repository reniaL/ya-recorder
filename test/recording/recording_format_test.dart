import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/storage/app_storage_paths.dart';

void main() {
  test('formats keep stable wire names, extensions and MIME types', () {
    expect(RecordingFormat.m4a.wireName, 'm4a');
    expect(RecordingFormat.m4a.mimeType, 'audio/mp4');
    expect(RecordingFormat.mp3.wireName, 'mp3');
    expect(RecordingFormat.mp3.mimeType, 'audio/mpeg');
    for (final format in RecordingFormat.values) {
      expect(RecordingFormat.fromWireValue(format.wireName), format);
      expect(format.matchesCompletedPath('one.${format.extension}'), isTrue);
      expect(
        format.matchesCompletedPath('one.${format.extension}.part'),
        isFalse,
      );
    }
    for (final value in [null, 'wav', 'M4A', 42]) {
      expect(() => RecordingFormat.fromWireValue(value), throwsFormatException);
    }
  });

  test(
    'both format paths remain in their own completed and recovery directories',
    () {
      final paths = AppStoragePaths(
        Directory(path.join(Directory.systemTemp.path, 'format-paths')),
      );
      for (final format in RecordingFormat.values) {
        expect(
          paths.completedRecordingFile('one', format: format).path,
          path.join(
            paths.recordingsDirectory.path,
            'recording-one.${format.extension}',
          ),
        );
        expect(
          paths.temporaryRecordingFile('one', format: format).path,
          path.join(
            paths.recoveryDirectory.path,
            'recording-one.${format.extension}.part',
          ),
        );
        for (final id in ['', '../one', 'one/two', r'one\two']) {
          expect(
            () => paths.temporaryRecordingFile(id, format: format),
            throwsArgumentError,
          );
        }
      }
    },
  );
}
