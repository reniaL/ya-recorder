import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/settings/app_language.dart';
import 'package:ya_recorder/storage/models/recording.dart';
import 'package:ya_recorder/storage/recording_store.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late String databasePath;
  late RecordingStore store;
  final folders = [
    {'id': 'one', 'name': 'One', 'created_at': 100, 'sort_order': 5},
    {'id': 'two', 'name': 'Two', 'created_at': 200, 'sort_order': 2},
  ];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ya-aac-migration-');
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

  Future<Database> inspectDatabase() => databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    ),
  );

  // Actual pre-AAC tables rather than downgrading a database made by new code.
  Future<List<Map<String, Object?>>> createLegacy(
    int version,
    String? preference,
  ) async {
    final rows = <Map<String, Object?>>[];
    for (final format in [RecordingFormat.m4a, RecordingFormat.mp3]) {
      final file = File(path.join(directory.path, 'old.${format.extension}'));
      await file.writeAsBytes([1, 2, 3]);
      rows.add({
        'id': format.wireName,
        'title': 'Original ${format.label}',
        'file_path': file.path,
        'format': format.wireName,
        'created_at': 1000,
        'duration_ms': 2000,
        'file_size_bytes': 3,
        'folder_id': 'one',
        'deleted_at': format == RecordingFormat.mp3 ? 3000 : null,
        'was_interrupted': format == RecordingFormat.mp3 ? 1 : 0,
      });
    }
    await File(
      path.join(directory.path, 'recording-old.m4a.part'),
    ).writeAsBytes([8, 9]);
    await File(
      path.join(directory.path, 'old.draft'),
    ).writeAsString('format=m4a\nphase=CAPTURING\n');
    final db = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await db.execute(
            '''CREATE TABLE folders (
          id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL COLLATE NOCASE UNIQUE,
          created_at INTEGER NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)''',
          );
          await db.execute(
            '''CREATE TABLE recordings (
          id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, file_path TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL, duration_ms INTEGER NOT NULL CHECK(duration_ms >= 0),
          file_size_bytes INTEGER NOT NULL CHECK(file_size_bytes >= 0),
          format TEXT NOT NULL DEFAULT 'm4a' CHECK(format IN ('m4a', 'mp3')),
          folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL, deleted_at INTEGER,
          was_interrupted INTEGER NOT NULL DEFAULT 0 CHECK(was_interrupted IN (0, 1)))''',
          );
          await db.execute(
            'CREATE INDEX recordings_active_by_folder_and_date ON recordings(folder_id, deleted_at, created_at DESC)',
          );
          await db.execute(
            'CREATE INDEX recordings_deleted_by_date ON recordings(deleted_at DESC)',
          );
          for (final folder in folders) {
            await db.insert('folders', folder);
          }
          for (final row in rows) {
            await db.insert('recordings', row);
          }
          if (version >= 4) {
            await db.execute(
              '''CREATE TABLE recording_preferences (
            id INTEGER PRIMARY KEY CHECK(id = 1),
            default_format TEXT NOT NULL CHECK(default_format IN ('m4a', 'mp3')))''',
            );
            if (preference != null) {
              await db.insert('recording_preferences', {
                'id': 1,
                'default_format': preference,
              });
            }
          }
          if (version >= 5) {
            await db.execute(
              '''CREATE TABLE app_preferences (
            id INTEGER PRIMARY KEY CHECK(id = 1),
            theme_mode TEXT NOT NULL CHECK(theme_mode IN ('system', 'light', 'dark'))
            ${version >= 6 ? ", language TEXT NOT NULL DEFAULT 'zh' CHECK(language IN ('zh', 'en'))" : ''})''',
            );
            await db.insert('app_preferences', {
              'id': 1,
              'theme_mode': 'dark',
              if (version >= 6) 'language': 'en',
            });
          }
        },
      ),
    );
    await db.close();
    return rows;
  }

  for (final version in [3, 4, 5, 6]) {
    for (final preference
        in version == 3 ? <String?>[null] : <String?>[null, 'm4a', 'mp3']) {
      test(
        'v$version / ${preference ?? 'no preference'} migrates to AAC without changing old data',
        () async {
          final rows = await createLegacy(version, preference);
          await store.open();
          expect(
            await store.getDefaultRecordingFormat(),
            preference == 'mp3' ? RecordingFormat.mp3 : RecordingFormat.aac,
          );
          final actual = [
            ...await store.listRecordings(),
            ...await store.listRecentlyDeleted(),
          ]..sort((a, b) => a.id.compareTo(b.id));
          expect(actual.map((item) => item.toDatabaseMap()), rows);
          expect(
            (await store.listFolders()).map((item) => item.toDatabaseMap()),
            folders.reversed,
          );
          expect(
            await store.getThemeMode(),
            version >= 5 ? ThemeMode.dark : ThemeMode.system,
          );
          expect(
            await store.getAppLanguage(),
            version >= 6 ? AppLanguage.english : AppLanguage.simplifiedChinese,
          );
          for (final row in rows) {
            expect(await File(row['file_path']! as String).readAsBytes(), [
              1,
              2,
              3,
            ]);
          }
          expect(
            await File(
              path.join(directory.path, 'recording-old.m4a.part'),
            ).readAsBytes(),
            [8, 9],
          );
          expect(
            await File(path.join(directory.path, 'old.draft')).readAsString(),
            'format=m4a\nphase=CAPTURING\n',
          );

          final db = await inspectDatabase();
          try {
            expect(await db.getVersion(), 7);
            expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
            final indexes = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'recordings'",
            );
            expect(
              indexes.map((row) => row['name']),
              containsAll([
                'recordings_active_by_folder_and_date',
                'recordings_deleted_by_date',
              ]),
            );
          } finally {
            await db.close();
          }
          final file = File(path.join(directory.path, 'new.aac'));
          await file.writeAsBytes([4, 5]);
          final aac = Recording(
            id: 'aac',
            title: 'AAC',
            filePath: file.path,
            format: RecordingFormat.aac,
            createdAt: DateTime.utc(2026, 10, 12),
            duration: const Duration(seconds: 1),
            fileSizeBytes: 2,
            folderId: 'two',
          );
          await store.saveRecording(aac);
          await store.setDefaultRecordingFormat(RecordingFormat.aac);
          await store.close();
          expect(await store.getDefaultRecordingFormat(), RecordingFormat.aac);
          expect(
            (await store.listRecordings())
                .singleWhere((item) => item.id == 'aac')
                .toDatabaseMap(),
            aac.toDatabaseMap(),
          );
        },
      );
    }
  }

  test(
    'invalid old preference rolls back rebuilt tables and permits repair and retry',
    () async {
      final rows = await createLegacy(6, 'm4a');
      var db = await inspectDatabase();
      await db.execute('PRAGMA ignore_check_constraints = ON');
      await db.update('recording_preferences', {'default_format': 'wav'});
      await db.execute('PRAGMA ignore_check_constraints = OFF');
      await db.close();
      await expectLater(store.open(), throwsA(isA<DatabaseException>()));
      db = await inspectDatabase();
      try {
        expect(await db.getVersion(), 6);
        expect(await db.query('recordings', orderBy: 'id'), rows);
        expect(
          (await db.query('recording_preferences')).single['default_format'],
          'wav',
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        expect(
          await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE name IN ('recordings_v7', 'recording_preferences_v7')",
          ),
          isEmpty,
        );
        // Rollback restores the old CHECK, not only the old rows and version.
        await expectLater(
          db.insert('recordings', {
            ...rows.first,
            'id': 'test',
            'file_path': 'test.aac',
            'format': 'aac',
          }),
          throwsA(isA<DatabaseException>()),
        );
        await db.update('recording_preferences', {'default_format': 'm4a'});
      } finally {
        await db.close();
      }
      await store.open();
      expect(await store.getDefaultRecordingFormat(), RecordingFormat.aac);
      expect(
        (await store.listRecentlyDeleted()).single.toDatabaseMap(),
        rows.last,
      );
    },
  );

  test(
    'v7 retains foreign keys, unique paths and format constraints',
    () async {
      final rows = await createLegacy(6, 'mp3');
      await store.open();
      final db = await inspectDatabase();
      try {
        for (final change in [
          {'file_path': 'new.aac', 'format': 'wav'},
          {'file_path': 'new.aac', 'format': 'aac', 'folder_id': 'missing'},
          {'format': 'aac'}, // Duplicate original file path.
        ]) {
          await expectLater(
            db.insert('recordings', {...rows.first, 'id': 'new', ...change}),
            throwsA(isA<DatabaseException>()),
          );
        }
        await db.delete('folders', where: 'id = ?', whereArgs: ['one']);
        expect(
          (await db.query('recordings')).map((row) => row['folder_id']),
          everyElement(isNull),
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        await expectLater(
          db.insert('recording_preferences', {
            'id': 1,
            'default_format': 'wav',
          }, conflictAlgorithm: ConflictAlgorithm.replace),
          throwsA(isA<DatabaseException>()),
        );
        expect(await store.getDefaultRecordingFormat(), RecordingFormat.mp3);
      } finally {
        await db.close();
      }
    },
  );
}
