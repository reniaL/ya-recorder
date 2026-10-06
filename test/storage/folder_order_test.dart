import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/storage/models/recording.dart';
import 'package:ya_recorder/storage/recording_store.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late String databasePath;
  late RecordingStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('folder-order-');
    databasePath = path.join(directory.path, 'index.db');
    store = RecordingStore(
      databasePath: databasePath,
      databaseFactory: databaseFactoryFfi,
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<List<String>> ids() async =>
      (await store.listFolders()).map((f) => f.id).toList();
  Future<void> seed() async {
    for (final id in ['a', 'b', 'c']) {
      await store.createFolder(id: id, name: id);
    }
  }

  test(
    'order survives restart, rename, append and delete without changing audio',
    () async {
      await seed();
      final audio = File(path.join(directory.path, 'audio.m4a'));
      await audio.writeAsBytes([1, 2, 3]);
      final recording = Recording(
        id: 'recording',
        title: 'Original',
        filePath: audio.path,
        createdAt: DateTime.utc(2026, 10, 6),
        duration: const Duration(seconds: 10),
        fileSizeBytes: 3,
        folderId: 'c',
      );
      await store.saveRecording(recording);
      await store.reorderFolders(['c', 'a', 'b']);
      await store.close();
      expect(await ids(), ['c', 'a', 'b']);
      await store.renameFolder(folderId: 'c', name: 'Zebra');
      await store.createFolder(id: 'd', name: 'Aardvark');
      await store.deleteFolder(folderId: 'a');
      expect(await ids(), ['c', 'b', 'd']);
      expect(
        (await store.listRecordings()).single.toDatabaseMap(),
        recording.toDatabaseMap(),
      );
      expect(await audio.readAsBytes(), [1, 2, 3]);
    },
  );

  test(
    'invalid sets and a mid-transaction write failure preserve entire order',
    () async {
      await seed();
      for (final invalid in [
        ['b', 'a'],
        ['a', 'a', 'c'],
        ['c', 'a', 'missing'],
      ]) {
        await expectLater(store.reorderFolders(invalid), throwsStateError);
        expect(await ids(), ['a', 'b', 'c']);
      }
      final database = await databaseFactoryFfi.openDatabase(databasePath);
      await database.execute(
        "CREATE TRIGGER fail_order BEFORE UPDATE OF sort_order ON folders WHEN NEW.id = 'a' BEGIN SELECT RAISE(ABORT, 'write failure'); END",
      );
      await expectLater(
        store.reorderFolders(['c', 'a', 'b']),
        throwsA(isA<DatabaseException>()),
      );
      expect(await ids(), ['a', 'b', 'c']);
      await database.execute('DROP TRIGGER fail_order');
      await store.reorderFolders(['c', 'a', 'b']);
      expect(await ids(), ['c', 'a', 'b']);
    },
  );

  test('version one migration preserves name order, metadata and audio', () async {
    final audio = File(path.join(directory.path, 'legacy.m4a'));
    await audio.writeAsBytes([4, 5, 6]);
    final recording = Recording(
      id: 'legacy',
      title: 'Legacy recording',
      filePath: audio.path,
      createdAt: DateTime.utc(2026, 9, 30),
      duration: const Duration(seconds: 20),
      fileSizeBytes: 3,
      folderId: 'z',
      wasInterrupted: true,
    );
    final database = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE folders (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL COLLATE NOCASE UNIQUE, created_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE recordings (id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, file_path TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL, duration_ms INTEGER NOT NULL, file_size_bytes INTEGER NOT NULL, folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL, deleted_at INTEGER, was_interrupted INTEGER NOT NULL DEFAULT 0)',
          );
          await db.insert('folders', {
            'id': 'z',
            'name': 'Zulu',
            'created_at': 1,
          });
          await db.insert('folders', {
            'id': 'a',
            'name': 'alpha',
            'created_at': 2,
          });
          await db.insert('folders', {
            'id': 'b',
            'name': 'Bravo',
            'created_at': 3,
          });
          await db.insert('recordings', recording.toDatabaseMap());
        },
      ),
    );
    await database.close();
    expect(await ids(), ['a', 'b', 'z']);
    expect((await store.listFolders()).map((f) => f.sortOrder), [0, 1, 2]);
    expect(
      (await store.listRecordings()).single.toDatabaseMap(),
      recording.toDatabaseMap(),
    );
    expect(await audio.readAsBytes(), [4, 5, 6]);
    await store.reorderFolders(['z', 'b', 'a']);
    await store.close();
    expect(await ids(), ['z', 'b', 'a']);
  });
}
