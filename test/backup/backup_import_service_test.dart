import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/backup/backup_contract.dart' as contract;
import 'package:ya_recorder/backup/backup_document_service.dart';
import 'package:ya_recorder/backup/backup_import_service.dart';
import 'package:ya_recorder/backup/backup_progress.dart';
import 'package:ya_recorder/backup/library_coordinator.dart';
import 'package:ya_recorder/recording/recording_service.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/storage/app_storage_paths.dart';
import 'package:ya_recorder/storage/recording_store.dart';

import 'backup_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  const bridge = MethodChannel('test/import');
  const recorderBridge = MethodChannel('test/import-recording');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const id = '11111111-1111-4111-8111-111111111111';
  late AppStoragePaths paths;
  late RecordingStore store;
  late RecordingService recording;
  late BackupImportService importer;
  late BackupImportRecovery recovery;
  late BackupFixture fixture;
  late Map<String, Object?> state;
  late List<String> calls;
  late int failAfterFile;
  late bool failAccept;
  late bool corruptHash;
  late int taskCounter;

  Future<void> writeReport() async {
    fixture.assemble();
    final content = {
      'manifest.json': fixture.manifestBytes,
      'metadata.json': fixture.metadataBytes,
      ...fixture.audio,
    };
    await File(
      path.join(paths.rootDirectory.path, 'verified.json'),
    ).writeAsString(
      jsonEncode({
        'manifest': utf8.decode(fixture.manifestBytes),
        'metadata': utf8.decode(fixture.metadataBytes),
        'entries': [
          for (final e in content.entries)
            {
              'path': e.key,
              'size': e.value.length,
              'sha256': corruptHash && e.key.endsWith('.aac')
                  ? '0' * 64
                  : sha256.convert(e.value).toString(),
            },
        ],
      }),
    );
  }

  Future<BackupImportResult> run({
    Future<bool> Function(BackupImportPlan)? confirm,
  }) => importer.import(
    store: store,
    recordingService: recording,
    paths: paths,
    source: const BackupDocument(
      uri: 'content://provider/test',
      displayName: 'test.zip',
    ),
    confirm: confirm ?? (_) async => true,
  );

  setUp(() async {
    paths = AppStoragePaths(
      await Directory.systemTemp.createTemp('import-test-'),
    );
    await paths.ensureDirectories();
    store = RecordingStore(
      databasePath: paths.databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    recording = RecordingService(commands: recorderBridge);
    importer = BackupImportService(
      documents: BackupDocumentService(
        commands: bridge,
        pollInterval: Duration.zero,
      ),
    );
    recovery = BackupImportRecovery(paths, store);
    fixture = BackupFixture();
    calls = [];
    taskCounter = 0;
    failAfterFile = -1;
    failAccept = false;
    corruptHash = false;
    state = {
      'taskId': id,
      'sequence': 0,
      'status': 'prepared',
      'processedBytes': 0,
      'stagedPath': path.join(paths.rootDirectory.path, 'payload.zip'),
    };
    messenger.setMockMethodCallHandler(
      recorderBridge,
      (_) async => {'state': 'idle', 'elapsedMs': 0, 'canResume': false},
    );
    messenger.setMockMethodCallHandler(bridge, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'prepare':
          if (taskCounter++ > 0) {
            state['taskId'] =
                '11111111-1111-4111-8111-${taskCounter.toString().padLeft(12, '0')}';
          }
          state['status'] = 'prepared';
          return Map.of(state);
        case 'startImport':
          await writeReport();
          state.addAll({
            'status': 'completed',
            'sequence': (state['sequence'] as int) + 1,
          });
          return Map.of(state);
        case 'placeImport':
          final files = (call.arguments as Map)['files'] as List;
          for (var i = 0; i < files.length; i++) {
            await File(
              files[i]['target'] as String,
            ).writeAsBytes([1, 2, 3], flush: true);
            if (i == failAfterFile) {
              state['status'] = 'failed';
              return Map.of(state);
            }
          }
          state['status'] = 'completed';
          return Map.of(state);
        case 'snapshot':
          return Map.of(state);
        case 'accept':
          if (failAccept) {
            throw PlatformException(code: 'lost-engine-after-commit');
          }
          return null;
        case 'release':
          expect(store.coordinator.isProtected, isTrue);
          return Map.of(state);
        default:
          return null;
      }
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(bridge, null);
    messenger.setMockMethodCallHandler(recorderBridge, null);
    await store.close();
    await paths.rootDirectory.delete(recursive: true);
  });

  test(
    'three formats, metadata, empty folders and repeat import are preserved',
    () async {
      final result = await run(
        confirm: (plan) async {
          expect(await store.listRecordings(), isEmpty);
          expect(await store.listFolders(), isEmpty);
          expect(plan.recordings.length, 3);
          await expectLater(
            store.createFolder(id: 'x', name: 'X'),
            throwsA(isA<LibraryBusyException>()),
          );
          return true;
        },
      );
      expect(result.cleanupPending, isFalse);
      final rows = await store.listRecordings();
      expect(rows.length, 3);
      expect((await store.listFolders()).length, 2);
      for (final row in rows) {
        expect(await File(row.filePath).readAsBytes(), [1, 2, 3]);
      }
      final repeat = await run();
      expect(repeat.plan.duplicates, 3);
      expect(repeat.hasAdditions, isFalse);
      expect((await store.listRecordings()).length, 3);
      expect(await store.importWasCommitted(id), isFalse);
    },
  );

  test(
    'recently deleted IDs and changed metadata skip without restoring or overwriting',
    () async {
      await run();
      await store.softDeleteRecording(
        recordingId: 'sample-aac',
        deletedAt: DateTime.now().toUtc(),
      );
      await store.renameRecording(
        recordingId: 'sample-mp3',
        title: 'Local title',
      );
      final result = await run();
      expect(result.plan.duplicates, 2);
      expect(result.plan.conflicts, 1);
      expect((await store.listRecordings()).length, 2);
      expect((await store.listRecentlyDeleted()).length, 1);
    },
  );

  test(
    'SQLite NOCASE suffix increments and existing folder order stays intact',
    () async {
      await store.createFolder(id: 'local', name: 'Empty FOLDER');
      await store.createFolder(id: 'suffix', name: 'Empty folder（导入）');
      final result = await run();
      expect(result.plan.renamedFolders.values.single, 'Empty folder（导入 2）');
      final folders = await store.listFolders();
      expect(folders.take(2).map((f) => f.id), ['local', 'suffix']);
      expect(folders.last.name, 'Empty folder（导入 2）');
    },
  );

  test('all files are validated before ID skipping or confirmation', () async {
    await run();
    corruptHash = true;
    await expectLater(
      run(confirm: (_) async => fail('must not preview corruption')),
      throwsA(isA<contract.BackupValidationException>()),
    );
    expect((await store.listRecordings()).length, 3);
  });

  test(
    'missing local audio for duplicate ID is explicit and does not repair it',
    () async {
      await run();
      final row = (await store.listRecordings()).first;
      await File(row.filePath).delete();
      await expectLater(run(), throwsStateError);
      expect((await store.listRecordings()).length, 3);
    },
  );

  test('orphan canonical file is never overwritten', () async {
    final f = paths.completedRecordingFile(
      'sample-aac',
      format: RecordingFormat.aac,
    );
    await f.writeAsBytes([9]);
    await expectLater(run(), throwsStateError);
    expect(await f.readAsBytes(), [9]);
    expect(await store.listRecordings(), isEmpty);
  });

  test(
    'cancellation wakes an indefinitely waiting confirmation and releases gate',
    () async {
      final waiting = Completer<bool>();
      await expectLater(
        run(
          confirm: (_) {
            store.coordinator.requestCancel(store.coordinator.activeTask!);
            return waiting.future;
          },
        ),
        throwsA(isA<BackupCancelledException>()),
      );
      expect(calls, isNot(contains('placeImport')));
      expect(store.coordinator.isProtected, isFalse);
    },
  );

  for (var index = 0; index < 3; index++) {
    test(
      'failure after file $index cleans only owned files and inserts no rows',
      () async {
        failAfterFile = index;
        await expectLater(run(), throwsA(isA<BackupTransferException>()));
        expect(await recovery.destination(id).exists(), isFalse);
        expect(await recovery.journal(id).exists(), isFalse);
        expect(await store.listRecordings(), isEmpty);
        expect(await store.listFolders(), isEmpty);
      },
    );
  }

  test(
    'transaction failure rolls back folders, recordings and commit marker',
    () async {
      await store.open();
      final db = await databaseFactoryFfi.openDatabase(paths.databasePath);
      await db.execute(
        "CREATE TRIGGER fail_import BEFORE INSERT ON recordings WHEN NEW.id = 'sample-mp3' BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(run(), throwsA(isA<DatabaseException>()));
      expect(await store.listRecordings(), isEmpty);
      expect(await store.listFolders(), isEmpty);
      expect(await store.importWasCommitted(id), isFalse);
      expect(await recovery.destination(id).exists(), isFalse);
    },
  );

  test(
    'postcommit bridge failure preserves successful audio and result',
    () async {
      failAccept = true;
      final result = await run();
      expect(result.cleanupPending, isTrue);
      expect(store.coordinator.progress?.stage, BackupStage.completed);
      expect(store.coordinator.lastError, isNull);
      expect(store.coordinator.lastResult, same(result));
      expect((await store.listRecordings()).length, 3);
      for (final r in await store.listRecordings()) {
        expect(await File(r.filePath).exists(), isTrue);
      }
    },
  );

  test(
    'startup commit authority preserves files even without COMMITTED journal text',
    () async {
      await recovery.prepare(id, ['recording-new.aac']);
      final f = File(
        path.join(recovery.destination(id).path, 'recording-new.aac'),
      );
      await f.writeAsBytes([1, 2, 3]);
      await store.coordinator.runBackup(
        taskId: id,
        operation: BackupOperation.import,
        recordingIsIdle: () async => true,
        action: (lease) => store.backupTransaction(lease, (txn) async {
          await txn.insert('backup_import_commits', {
            'task_id': id,
            'committed_at': 1,
          });
        }),
      );
      await store.close();
      await recovery.recover();
      expect(await f.exists(), isTrue);
      expect(await recovery.journal(id).exists(), isFalse);
    },
  );

  test(
    'uncommitted restart cleans partial files idempotently; unrelated file survives',
    () async {
      final unrelated = File(
        path.join(paths.recordingsDirectory.path, 'old.aac'),
      );
      await unrelated.writeAsBytes([9]);
      await recovery.prepare(id, ['recording-new.aac']);
      await File(
        path.join(recovery.destination(id).path, 'recording-new.aac'),
      ).writeAsBytes([1]);
      await store.close();
      await recovery.recover();
      await recovery.recover();
      expect(await unrelated.readAsBytes(), [9]);
      expect(await recovery.destination(id).exists(), isFalse);
    },
  );

  test(
    'ambiguous ownership and interrupted cleanup retain journal for retry',
    () async {
      await recovery.prepare(id, ['recording-new.aac']);
      final other = File(
        path.join(recovery.destination(id).path, 'unknown.aac'),
      );
      await other.writeAsBytes([9]);
      await expectLater(recovery.recover(), throwsStateError);
      expect(await recovery.journal(id).exists(), isTrue);
      expect(await other.readAsBytes(), [9]);
      await other.delete();
      await recovery.recover();
      expect(await recovery.journal(id).exists(), isFalse);
    },
  );

  test('empty library still restores empty folders', () async {
    fixture = BackupFixture(empty: true);
    final result = await run();
    expect(result.plan.recordings, isEmpty);
    expect(result.plan.folders.length, 2);
    expect(result.hasAdditions, isTrue);
    expect(calls, isNot(contains('placeImport')));
  });

  test('committing phase refuses late cancellation', () async {
    recording.bindLibraryCoordinator(store.coordinator);
    void listener() {
      if (store.coordinator.progress?.stage == BackupStage.committing) {
        store.coordinator.requestCancel(store.coordinator.activeTask!);
      }
    }

    store.coordinator.addListener(listener);
    final result = await run();
    store.coordinator.removeListener(listener);
    expect(result.plan.recordings.length, 3);
    expect(store.coordinator.progress?.stage, BackupStage.completed);
  });

  test(
    'journal COMMITTED text without SQLite marker cannot keep uncommitted files',
    () async {
      await recovery.prepare(id, ['recording-new.aac', 'recording-other.mp3']);
      final f = File(
        path.join(recovery.destination(id).path, 'recording-new.aac'),
      );
      await f.writeAsBytes([1]);
      final journal = recovery.journal(id);
      final value =
          jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
      value['state'] = 'COMMITTED';
      await journal.writeAsString(jsonEncode(value), flush: true);
      // The absent second file also models an interruption halfway through cleanup.
      await recovery.recover();
      expect(await f.exists(), isFalse);
      expect(await journal.exists(), isFalse);
    },
  );

  test(
    'v7 upgrade only adds commit table and preserves audio, rows and preferences',
    () async {
      await run();
      await store.setDefaultRecordingFormat(RecordingFormat.mp3);
      final before = (await store.listRecordings())
          .map((r) => r.toDatabaseMap())
          .toList();
      final folders = (await store.listFolders())
          .map((f) => f.toDatabaseMap())
          .toList();
      await store.close();
      final db = await databaseFactoryFfi.openDatabase(paths.databasePath);
      await db.execute('DROP TABLE backup_import_commits');
      await db.execute('PRAGMA user_version = 7');
      await db.close();
      await store.open();
      expect(
        (await store.listRecordings()).map((r) => r.toDatabaseMap()).toList(),
        before,
      );
      expect(
        (await store.listFolders()).map((f) => f.toDatabaseMap()).toList(),
        folders,
      );
      expect(await store.getDefaultRecordingFormat(), RecordingFormat.mp3);
      expect(await store.importWasCommitted(id), isFalse);
      for (final r in await store.listRecordings()) {
        expect(await File(r.filePath).readAsBytes(), [1, 2, 3]);
      }
    },
  );
}
