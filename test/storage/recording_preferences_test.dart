import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart' show ThemeMode;
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

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ya-preferences-');
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

  Future<Database> database() => databaseFactoryFfi.openDatabase(databasePath);

  test(
    'language persists and concurrent writes preserve theme and format',
    () async {
      expect(await store.getAppLanguage(), AppLanguage.simplifiedChinese);
      await store.setDefaultRecordingFormat(RecordingFormat.mp3);
      await Future.wait([
        store.setThemeMode(ThemeMode.dark),
        store.setAppLanguage(AppLanguage.english),
      ]);
      await store.close();
      expect(await store.getAppLanguage(), AppLanguage.english);
      expect(await store.getThemeMode(), ThemeMode.dark);
      expect(await store.getDefaultRecordingFormat(), RecordingFormat.mp3);
      await store.setThemeMode(ThemeMode.light);
      expect(await store.getAppLanguage(), AppLanguage.english);
      await store.setAppLanguage(AppLanguage.simplifiedChinese);
      expect(await store.getThemeMode(), ThemeMode.light);
    },
  );

  test(
    'v5 upgrade keeps theme, format, folder data; failed language update rolls back',
    () async {
      await store.setThemeMode(ThemeMode.dark);
      await store.setDefaultRecordingFormat(RecordingFormat.mp3);
      final folder = await store.createFolder(
        id: 'language-upgrade',
        name: 'Preserved',
      );
      var db = await database();
      await db.execute('ALTER TABLE app_preferences DROP COLUMN language');
      await db.setVersion(5);
      await store.close();
      expect(await store.getAppLanguage(), AppLanguage.simplifiedChinese);
      expect(await store.getThemeMode(), ThemeMode.dark);
      expect(await store.getDefaultRecordingFormat(), RecordingFormat.mp3);
      expect(
        (await store.listFolders()).single.toDatabaseMap(),
        folder.toDatabaseMap(),
      );
      db = await database();
      await db.execute(
        "CREATE TRIGGER fail_language BEFORE UPDATE OF language ON app_preferences BEGIN SELECT RAISE(ABORT, 'write failed'); END",
      );
      await expectLater(
        store.setAppLanguage(AppLanguage.english),
        throwsA(isA<DatabaseException>()),
      );
      expect(await store.getAppLanguage(), AppLanguage.simplifiedChinese);
      expect(await store.getThemeMode(), ThemeMode.dark);
      await db.execute('DROP TRIGGER fail_language');
      await store.setAppLanguage(AppLanguage.english);
      await store.close();
      expect(await store.getAppLanguage(), AppLanguage.english);
    },
  );

  test(
    'theme defaults to system and persists independently of format',
    () async {
      expect(await store.getThemeMode(), ThemeMode.system);
      await store.setDefaultRecordingFormat(RecordingFormat.mp3);
      for (final mode in ThemeMode.values) {
        await store.setThemeMode(mode);
        await store.close();
        expect(await store.getThemeMode(), mode);
        expect(await store.getDefaultRecordingFormat(), RecordingFormat.mp3);
        await store.setDefaultRecordingFormat(RecordingFormat.m4a);
        expect(await store.getThemeMode(), mode);
        await store.setDefaultRecordingFormat(RecordingFormat.mp3);
      }
    },
  );

  test(
    'v4 upgrade preserves format and folders; failed theme writes retry',
    () async {
      await store.setDefaultRecordingFormat(RecordingFormat.mp3);
      final folder = await store.createFolder(id: 'keep', name: '保留');
      var db = await database();
      await db.execute('DROP TABLE app_preferences');
      await db.setVersion(4);
      await store.close();
      expect(await store.getThemeMode(), ThemeMode.system);
      expect(await store.getDefaultRecordingFormat(), RecordingFormat.mp3);
      expect(
        (await store.listFolders()).single.toDatabaseMap(),
        folder.toDatabaseMap(),
      );
      await store.setThemeMode(ThemeMode.dark);
      db = await database();
      await db.execute(
        '''CREATE TRIGGER fail_theme BEFORE INSERT ON app_preferences
      BEGIN SELECT RAISE(ABORT, 'write failed'); END''',
      );
      await expectLater(
        store.setThemeMode(ThemeMode.light),
        throwsA(isA<DatabaseException>()),
      );
      expect(await store.getThemeMode(), ThemeMode.dark);
      await db.execute('DROP TRIGGER fail_theme');
      await store.setThemeMode(ThemeMode.light);
      expect(await store.getThemeMode(), ThemeMode.light);
    },
  );

  test(
    'fresh defaults to AAC; successful changes persist after reopening',
    () async {
      expect(await store.getDefaultRecordingFormat(), RecordingFormat.aac);
      for (final format in RecordingFormat.values) {
        await store.setDefaultRecordingFormat(format);
        await store.close();
        expect(await store.getDefaultRecordingFormat(), format);
      }
    },
  );

  test(
    'failed preference write retains previous value and can be retried',
    () async {
      await store.setDefaultRecordingFormat(RecordingFormat.m4a);
      final db = await database();
      await db.execute('''
      CREATE TRIGGER fail_preference BEFORE INSERT ON recording_preferences
      BEGIN SELECT RAISE(ABORT, 'write failed'); END
    ''');
      await expectLater(
        store.setDefaultRecordingFormat(RecordingFormat.mp3),
        throwsA(isA<DatabaseException>()),
      );
      expect(await store.getDefaultRecordingFormat(), RecordingFormat.m4a);
      await db.execute('DROP TRIGGER fail_preference');
      await store.setDefaultRecordingFormat(RecordingFormat.mp3);
      expect(await store.getDefaultRecordingFormat(), RecordingFormat.mp3);
    },
  );

  test(
    'v3 migration preserves mixed index, folder order and original audio',
    () async {
      final folder = await store.createFolder(id: 'folder', name: '工作');
      for (final format in [RecordingFormat.m4a, RecordingFormat.mp3]) {
        final file = File(
          path.join(directory.path, 'audio.${format.extension}'),
        );
        await file.writeAsBytes([1, 2, 3]);
        await store.saveRecording(
          Recording(
            id: format.wireName,
            title: '已有 ${format.label}',
            filePath: file.path,
            format: format,
            createdAt: DateTime.utc(2026, 10, 8),
            duration: const Duration(seconds: 3),
            fileSizeBytes: 3,
            folderId: folder.id,
          ),
        );
      }
      final before = (await store.listRecordings())
          .map((r) => r.toDatabaseMap())
          .toList();
      final db = await database();
      await db.execute('DROP TABLE recording_preferences');
      await db.execute('DROP TABLE app_preferences');
      await db.setVersion(3);
      await store.close();

      expect(await store.getDefaultRecordingFormat(), RecordingFormat.aac);
      await store.setDefaultRecordingFormat(RecordingFormat.mp3);
      expect(
        (await store.listRecordings()).map((r) => r.toDatabaseMap()).toList(),
        before,
      );
      expect(
        (await store.listFolders()).single.toDatabaseMap(),
        folder.toDatabaseMap(),
      );
      for (final format in [RecordingFormat.m4a, RecordingFormat.mp3]) {
        expect(
          await File(
            path.join(directory.path, 'audio.${format.extension}'),
          ).readAsBytes(),
          [1, 2, 3],
        );
      }
      expect(await (await database()).getVersion(), 7);
    },
  );

  test(
    'v3 failed migration rolls back version and leaves existing data',
    () async {
      final folder = await store.createFolder(id: 'one', name: '保留');
      final db = await database();
      await db.setVersion(3); // Existing table causes CREATE TABLE to fail.
      await store.close();
      await expectLater(store.open(), throwsA(isA<DatabaseException>()));
      final unchanged = await database();
      expect(await unchanged.getVersion(), 3);
      expect((await unchanged.query('folders')).single, folder.toDatabaseMap());
      await unchanged.close();
    },
  );
}
