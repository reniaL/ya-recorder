import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/storage/models/recording.dart';
import 'package:ya_recorder/storage/recording_store.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late String databasePath;
  late RecordingStore store;
  final now = DateTime.utc(2026, 10, 7);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ya-format-migration-');
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

  Future<List<Map<String, Object?>>> createLegacy(
    int version, {
    bool conflictingColumn = false,
  }) async {
    final rows = <Map<String, Object?>>[];
    for (var i = 0; i < 3; i++) {
      final file = File(path.join(directory.path, 'legacy-$i.m4a'));
      await file.writeAsBytes([i, 4, 8]);
      rows.add({
        'id': 'legacy-$i',
        'title': 'Legacy $i',
        'file_path': file.path,
        'created_at': now.subtract(Duration(hours: i)).millisecondsSinceEpoch,
        'duration_ms': 1000 + i,
        'file_size_bytes': 3,
        'folder_id': i == 2 ? null : 'z',
        'deleted_at': i == 1
            ? now.subtract(const Duration(days: 1)).millisecondsSinceEpoch
            : null,
        'was_interrupted': i == 1 ? 1 : 0,
      });
    }
    final db = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE folders (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL COLLATE NOCASE UNIQUE, created_at INTEGER NOT NULL${version == 2 ? ', sort_order INTEGER NOT NULL DEFAULT 0' : ''})',
          );
          await db.execute(
            'CREATE TABLE recordings (id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, file_path TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL, duration_ms INTEGER NOT NULL, file_size_bytes INTEGER NOT NULL, folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL, deleted_at INTEGER, was_interrupted INTEGER NOT NULL DEFAULT 0${conflictingColumn ? ', format TEXT' : ''})',
          );
          for (final entry in ['z', 'a'].indexed) {
            await db.insert('folders', {
              'id': entry.$2,
              'name': entry.$2 == 'z' ? 'Zulu' : 'Alpha',
              'created_at': 100 + entry.$1,
              if (version == 2) 'sort_order': entry.$1,
            });
          }
          for (final row in rows) {
            await db.insert('recordings', row);
          }
          await db.execute(
            'CREATE INDEX recordings_active_by_folder_and_date ON recordings(folder_id, deleted_at, created_at DESC)',
          );
          await db.execute(
            'CREATE INDEX recordings_deleted_by_date ON recordings(deleted_at DESC)',
          );
        },
      ),
    );
    await db.close();
    return rows;
  }

  for (final version in [1, 2]) {
    test(
      'v$version upgrade adds M4A without changing metadata, folders or files',
      () async {
        final original = await createLegacy(version);
        await store.open();
        final expected = original
            .map((row) => {...row, 'format': 'm4a'})
            .toList();
        final actual = [
          ...await store.listRecordings(),
          ...await store.listRecentlyDeleted(),
        ]..sort((a, b) => a.id.compareTo(b.id));
        expect(actual.map((recording) => recording.toDatabaseMap()), expected);
        expect(
          (await store.listFolders()).map((folder) => folder.id),
          version == 1 ? ['a', 'z'] : ['z', 'a'],
        );
        for (var i = 0; i < original.length; i++) {
          expect(
            await File(original[i]['file_path']! as String).readAsBytes(),
            [i, 4, 8],
          );
        }
        await store.close();
        await store.open();
        expect(
          (await store.listRecordings()).map((r) => r.format),
          everyElement(RecordingFormat.m4a),
        );
        expect(
          (await store.listRecentlyDeleted()).single.toDatabaseMap(),
          expected[1],
        );
        final db = await databaseFactoryFfi.openDatabase(
          databasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        try {
          expect(await db.getVersion(), 4);
          expect(
            (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'recordings_%'",
            )).length,
            2,
          );
        } finally {
          await db.close();
        }
      },
    );
  }

  test(
    'failed upgrade rolls back all changes and allows a clean retry',
    () async {
      final original = await createLegacy(1, conflictingColumn: true);
      await expectLater(store.open(), throwsA(isA<DatabaseException>()));
      final db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
        expect(await db.getVersion(), 1);
        expect(
          (await db.rawQuery(
            'PRAGMA table_info(folders)',
          )).map((row) => row['name']),
          isNot(contains('sort_order')),
        );
        expect(
          await db.query('recordings', orderBy: 'id'),
          original.map((row) => {...row, 'format': null}),
        );
        await db.execute('ALTER TABLE recordings DROP COLUMN format');
      } finally {
        await db.close();
      }
      await store.open();
      expect((await store.listRecordings()).length, 2);
      expect(
        (await store.listRecentlyDeleted()).single.format,
        RecordingFormat.m4a,
      );
      expect((await store.listFolders()).map((folder) => folder.id), [
        'a',
        'z',
      ]);
    },
  );

  test(
    'mixed formats retain their own metadata through management and restart',
    () async {
      await store.createFolder(id: 'folder', name: 'Folder');
      for (final format in RecordingFormat.values) {
        final file = File(
          path.join(directory.path, '${format.name}.${format.extension}'),
        );
        await file.writeAsBytes([1, 2, 3]);
        await store.saveRecording(
          Recording(
            id: format.name,
            title: format.name,
            filePath: file.path,
            format: format,
            createdAt: now,
            duration: const Duration(seconds: 2),
            fileSizeBytes: 3,
          ),
        );
        await store.renameRecording(
          recordingId: format.name,
          title: 'Renamed ${format.name}',
        );
      }
      await store.moveRecordings(
        recordingIds: ['m4a', 'mp3'],
        folderId: 'folder',
      );
      final before = (await store.listRecordings())
          .map((r) => r.toDatabaseMap())
          .toList();
      await store.softDeleteRecordings(
        recordingIds: ['m4a', 'mp3'],
        deletedAt: now,
      );
      await store.close();
      await store.open();
      expect(
        (await store.listRecentlyDeleted()).map((r) => r.format).toSet(),
        RecordingFormat.values.toSet(),
      );
      for (final format in RecordingFormat.values) {
        await store.restoreRecording(format.name, now: now);
        expect(
          await File(
            path.join(directory.path, '${format.name}.${format.extension}'),
          ).readAsBytes(),
          [1, 2, 3],
        );
      }
      expect(
        (await store.listRecordings()).map((r) => r.toDatabaseMap()),
        before,
      );
    },
  );

  test('invalid format or path never becomes an index entry', () async {
    final invalid = Recording(
      id: 'bad',
      title: 'bad',
      filePath: '/private/bad.m4a',
      format: RecordingFormat.mp3,
      createdAt: now,
      duration: const Duration(seconds: 1),
      fileSizeBytes: 10,
    );
    await expectLater(store.saveRecording(invalid), throwsArgumentError);
    expect(await store.listRecordings(), isEmpty);
    for (final value in [null, 'wav', 123]) {
      expect(
        () => Recording.fromDatabaseMap({
          ...invalid.toDatabaseMap(),
          'format': value,
        }),
        throwsFormatException,
      );
    }
    final db = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      for (final value in [null, 'wav']) {
        await expectLater(
          db.insert('recordings', {
            ...invalid.toDatabaseMap(),
            'format': value,
          }),
          throwsA(isA<DatabaseException>()),
        );
      }
      expect(await db.query('recordings'), isEmpty);
    } finally {
      await db.close();
    }
  });
}
