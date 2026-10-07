import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../recording/recording_format.dart';

class AppStoragePaths {
  AppStoragePaths(this.rootDirectory);

  final Directory rootDirectory;

  Directory get recordingsDirectory {
    return Directory(path.join(rootDirectory.path, 'recordings'));
  }

  Directory get recoveryDirectory {
    return Directory(path.join(rootDirectory.path, 'recovery'));
  }

  String get databasePath => path.join(rootDirectory.path, 'index.db');

  static Future<AppStoragePaths> create() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final paths = AppStoragePaths(
      Directory(path.join(supportDirectory.path, 'ya_recorder')),
    );
    await paths.ensureDirectories();
    return paths;
  }

  Future<void> ensureDirectories() async {
    await Future.wait([
      rootDirectory.create(recursive: true),
      recordingsDirectory.create(recursive: true),
      recoveryDirectory.create(recursive: true),
    ]);
  }

  File completedRecordingFile(
    String recordingId, {
    required RecordingFormat format,
  }) {
    return File(
      path.join(
        recordingsDirectory.path,
        '${_fileStem(recordingId)}.${format.extension}',
      ),
    );
  }

  File temporaryRecordingFile(
    String recordingId, {
    required RecordingFormat format,
  }) {
    return File(
      path.join(
        recoveryDirectory.path,
        '${_fileStem(recordingId)}.${format.extension}.part',
      ),
    );
  }

  String _fileStem(String recordingId) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(recordingId)) {
      throw ArgumentError.value(
        recordingId,
        'recordingId',
        'must contain only letters, numbers, underscores, or hyphens',
      );
    }

    return 'recording-$recordingId';
  }
}
