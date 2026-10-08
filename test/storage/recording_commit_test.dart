import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/storage/models/recording.dart';
import 'package:ya_recorder/storage/recording_store.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory root;
  late RecordingStore store;
  late Recording recording;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('recording-commit-');
    store = RecordingStore(
      databasePath: path.join(root.path, 'index.db'),
      databaseFactory: databaseFactoryFfi,
    );
    await store.open();
    final file = File(path.join(root.path, 'one.mp3'));
    await file.writeAsBytes(List.filled(128, 7));
    recording = Recording(
      id: 'one',
      title: 'default',
      filePath: file.path,
      createdAt: DateTime.utc(2026, 10, 8),
      duration: const Duration(seconds: 3),
      fileSizeBytes: 128,
      format: RecordingFormat.mp3,
      wasInterrupted: true,
    );
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  test('validated MP3 and M4A files commit and survive restart', () async {
    expect(await store.commitNativeRecording(recording), isTrue);
    final m4a = File(path.join(root.path, 'two.m4a'));
    await m4a.writeAsBytes([1, 2]);
    await store.commitNativeRecording(
      Recording(
        id: 'two',
        title: 'm4a',
        filePath: m4a.path,
        createdAt: recording.createdAt,
        duration: const Duration(seconds: 1),
        fileSizeBytes: 2,
        format: RecordingFormat.m4a,
      ),
    );
    await store.close();
    await store.open();
    final rows = await store.listRecordings();
    expect(rows.length, 2);
    expect(rows.map((r) => r.format).toSet(), {
      RecordingFormat.mp3,
      RecordingFormat.m4a,
    });
    expect(rows.singleWhere((r) => r.id == 'one').wasInterrupted, isTrue);
    expect(await store.commitNativeRecording(recording), isFalse);
  });

  test(
    'replay preserves user title, folder and recently deleted state',
    () async {
      await store.commitNativeRecording(recording);
      await store.createFolder(id: 'folder', name: 'folder');
      await store.renameRecording(recordingId: 'one', title: 'user title');
      await store.moveRecording(recordingId: 'one', folderId: 'folder');
      await store.softDeleteRecording(
        recordingId: 'one',
        deletedAt: DateTime.utc(2026, 10, 8),
      );
      expect(await store.commitNativeRecording(recording), isFalse);
      expect(await store.listRecordings(), isEmpty);
      final row = (await store.listRecentlyDeleted()).single;
      expect(row.title, 'user title');
      expect(row.folderId, 'folder');
      expect(row.isDeleted, isTrue);
    },
  );

  test('identity collisions never overwrite an existing recording', () async {
    await store.commitNativeRecording(recording);
    final collision = Recording(
      id: 'one',
      title: 'replacement',
      filePath: recording.filePath,
      createdAt: recording.createdAt,
      duration: const Duration(seconds: 99),
      fileSizeBytes: 128,
      format: RecordingFormat.mp3,
      wasInterrupted: true,
    );
    await expectLater(store.commitNativeRecording(collision), throwsStateError);
    expect((await store.listRecordings()).single.duration, recording.duration);
  });

  test(
    'missing, changed, empty and zero-duration audio cannot enter index',
    () async {
      await File(recording.filePath).delete();
      await expectLater(
        store.commitNativeRecording(recording),
        throwsStateError,
      );
      await File(recording.filePath).writeAsBytes([1]);
      await expectLater(
        store.commitNativeRecording(recording),
        throwsStateError,
      );
      await File(recording.filePath).writeAsBytes([]);
      await expectLater(
        store.commitNativeRecording(recording),
        throwsStateError,
      );
      expect(await store.listRecordings(), isEmpty);
    },
  );

  test('failed transaction preserves audio and can be replayed', () async {
    final db = await databaseFactoryFfi.openDatabase(store.databasePath);
    await db.execute(
      "CREATE TRIGGER fail_commit BEFORE INSERT ON recordings BEGIN SELECT RAISE(ABORT, 'simulated full disk'); END",
    );
    await expectLater(
      store.commitNativeRecording(recording),
      throwsA(isA<DatabaseException>()),
    );
    expect(await store.listRecordings(), isEmpty);
    expect(await File(recording.filePath).length(), 128);
    await db.execute('DROP TRIGGER fail_commit');
    expect(await store.commitNativeRecording(recording), isTrue);
  });
}
