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

  for (final format in RecordingFormat.values) {
    for (final folderExists in [true, false]) {
      test(
        'native $format commit keeps destination or falls back atomically ($folderExists)',
        () async {
          await store.createFolder(id: 'work', name: 'Work');
          if (!folderExists) await store.deleteFolder(folderId: 'work');
          final file = File(
            path.join(root.path, 'destination.${format.extension}'),
          );
          await file.writeAsBytes([1, 2]);
          final candidate = Recording(
            id: 'destination',
            title: 'new',
            filePath: file.path,
            createdAt: recording.createdAt,
            duration: const Duration(seconds: 1),
            fileSizeBytes: 2,
            format: format,
            folderId: 'work',
          );
          expect(await store.commitNativeRecording(candidate), isTrue);
          await store.close();
          await store.open();
          expect(
            (await store.listRecordings()).single.folderId,
            folderExists ? 'work' : null,
          );
          if (folderExists) {
            await store.moveRecording(recordingId: 'destination');
          }
          expect(await store.commitNativeRecording(candidate), isFalse);
          expect((await store.listRecordings()).single.folderId, isNull);
        },
      );
    }
  }

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

  test(
    'interrupted AAC commits once and preserves user metadata on replay after restart',
    () async {
      final file = File(path.join(root.path, 'recovered.aac'));
      await file.writeAsBytes([1, 2, 3]);
      final aac = Recording(
        id: 'aac',
        title: 'Recovered AAC',
        filePath: file.path,
        createdAt: DateTime.utc(2026, 10, 14),
        duration: const Duration(milliseconds: 3041),
        fileSizeBytes: 3,
        format: RecordingFormat.aac,
        wasInterrupted: true,
      );
      expect(await store.commitNativeRecording(aac), isTrue);
      await store.createFolder(id: 'aac-folder', name: 'AAC');
      await store.renameRecording(recordingId: 'aac', title: 'User title');
      await store.moveRecording(recordingId: 'aac', folderId: 'aac-folder');
      await store.softDeleteRecording(
        recordingId: 'aac',
        deletedAt: DateTime.utc(2026, 10, 14),
      );
      await store.close();
      await store.open();
      expect(await store.commitNativeRecording(aac), isFalse);
      final row = (await store.listRecentlyDeleted()).single;
      expect(row.format, RecordingFormat.aac);
      expect(row.duration, const Duration(milliseconds: 3041));
      expect(row.wasInterrupted, isTrue);
      expect(row.title, 'User title');
      expect(row.folderId, 'aac-folder');
      expect(await file.readAsBytes(), [1, 2, 3]);
    },
  );
}
