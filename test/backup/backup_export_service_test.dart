import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/backup/backup_contract.dart' as contract;
import 'package:ya_recorder/backup/backup_document_service.dart';
import 'package:ya_recorder/backup/backup_export_service.dart';
import 'package:ya_recorder/backup/backup_progress.dart';
import 'package:ya_recorder/backup/library_coordinator.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/recording/recording_service.dart';
import 'package:ya_recorder/storage/models/recording.dart';
import 'package:ya_recorder/storage/recording_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  const bridge = MethodChannel('test/export');
  const recordingBridge = MethodChannel('test/export-recording');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const destination = BackupDocument(
    uri: 'content://provider/export.zip',
    displayName: 'export.zip',
  );
  final now = DateTime.utc(2026, 10, 15, 6, 30);
  late Directory directory;
  late RecordingStore store;
  late RecordingService recording;
  late BackupExportService exporter;
  late Map<String, Object?> state;
  late List<String> calls;
  late Future<Object?> Function(MethodCall) handle;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('backup-export-');
    store = RecordingStore(
      databasePath: '${directory.path}/index.db',
      databaseFactory: databaseFactoryFfi,
    );
    await store.createFolder(id: 'folder-old', name: 'Old');
    await store.createFolder(id: 'folder-empty', name: 'Empty');
    for (final format in RecordingFormat.values) {
      final file = File(
        '${directory.path}/recording-${format.wireName}.${format.extension}',
      );
      await file.writeAsBytes([1, 2, 3]);
      await store.saveRecording(
        Recording(
          id: format.wireName,
          title: '标题 ${format.label}',
          filePath: file.path,
          createdAt: now,
          duration: const Duration(seconds: 1),
          fileSizeBytes: 3,
          format: format,
          folderId: 'folder-old',
          wasInterrupted: format == RecordingFormat.mp3,
        ),
      );
    }
    await store.saveRecording(
      Recording(
        id: 'deleted',
        title: 'Deleted',
        filePath: '${directory.path}/missing.aac',
        createdAt: now,
        duration: const Duration(seconds: 1),
        fileSizeBytes: 9,
        format: RecordingFormat.aac,
      ),
    );
    await store.softDeleteRecording(recordingId: 'deleted', deletedAt: now);
    state = {
      'taskId': 'export-task',
      'sequence': 0,
      'status': 'prepared',
      'processedBytes': 0,
      'stagedPath': '${directory.path}/payload.zip',
    };
    calls = [];
    recording = RecordingService(commands: recordingBridge);
    exporter = BackupExportService(
      documents: BackupDocumentService(
        commands: bridge,
        pollInterval: Duration.zero,
      ),
    );
    messenger.setMockMethodCallHandler(
      recordingBridge,
      (_) async => {'state': 'idle', 'elapsedMs': 0, 'canResume': false},
    );
    handle = (call) async {
      switch (call.method) {
        case 'prepare':
          return Map.of(state);
        case 'startExport':
          state.addAll({
            'kind': 'export',
            'accepted': true,
            'status': 'completed',
            'sequence': 2,
            'stage': 'saving',
            'processedBytes': 2048,
            'totalBytes': 2048,
            'cachedArchivePath': '${directory.path}/payload.zip',
            'retainedUntilMs': now
                .add(const Duration(hours: 24))
                .millisecondsSinceEpoch,
          });
          return Map.of(state);
        case 'snapshot':
          return Map.of(state);
        case 'cancel':
          if (state['status'] == 'running') {
            state.addAll({'status': 'cancelled', 'sequence': 3});
          }
          return null;
        case 'release':
          return Map.of(state);
        default:
          throw StateError('Unexpected platform call ${call.method}');
      }
    };
    messenger.setMockMethodCallHandler(bridge, (call) {
      calls.add(call.method);
      return handle(call);
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(bridge, null);
    messenger.setMockMethodCallHandler(recordingBridge, null);
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<BackupExportResult> export() => exporter.export(
    store: store,
    recordingService: recording,
    destination: destination,
    createdAt: now,
  );

  test(
    'protected SQLite snapshot exports three formats and empty folders, excluding deleted/settings/absolute paths',
    () async {
      final original = handle;
      handle = (call) async {
        if (call.method == 'startExport') {
          expect(store.coordinator.isProtected, isTrue);
          await expectLater(
            store.renameRecording(recordingId: 'aac', title: 'changed'),
            throwsA(isA<LibraryBusyException>()),
          );
          final args = Map<String, Object?>.from(
            (call.arguments as Map)['export'] as Map,
          );
          final metadata = args['metadataJson']! as String;
          expect(metadata, isNot(contains(directory.path)));
          expect(metadata, isNot(contains('deleted')));
          final decoded = jsonDecode(metadata) as Map;
          expect(decoded.keys, unorderedEquals(['recordings', 'folders']));
          expect((decoded['recordings'] as List).length, 3);
          expect((decoded['folders'] as List).length, 2);
          expect((args['sources'] as List).length, 3);
        }
        if (call.method == 'release') {
          expect(store.coordinator.isProtected, isTrue);
        }
        return original(call);
      };
      final result = await export();
      expect(result.recordingCount, 3);
      expect(result.folderCount, 2);
      expect(result.archiveBytes, 2048);
      expect(result.cachedArchivePath, endsWith('payload.zip'));
      expect(result.retainedUntil, now.add(const Duration(hours: 24)));
      expect(calls, isNot(contains('startCopy')));
      expect(store.coordinator.isProtected, isFalse);
      expect(
        (await store.listRecordings()).singleWhere((r) => r.id == 'aac').title,
        '标题 AAC',
      );
    },
  );

  test('active recording rejects export before native work', () async {
    messenger.setMockMethodCallHandler(
      recordingBridge,
      (_) async => {
        'state': 'paused',
        'sessionId': 'live',
        'format': 'aac',
        'elapsedMs': 1,
        'canResume': true,
      },
    );
    await expectLater(export(), throwsA(isA<LibraryBusyException>()));
    expect(calls, isNot(contains('startExport')));
    expect(calls.last, 'release');
  });

  test('source/native failure is never reported as export success', () async {
    final original = handle;
    handle = (call) async {
      if (call.method == 'startExport') {
        state.addAll({
          'status': 'failed',
          'sequence': 2,
          'error': 'backup-export-or-io-failed',
          'errorDetail': 'source-missing-or-inconsistent',
        });
        return Map.of(state);
      }
      return original(call);
    };
    await expectLater(export(), throwsA(isA<BackupTransferException>()));
    expect(store.coordinator.lastResult, isNull);
    expect(calls.last, 'release');
  });

  test(
    'cancel during export waits for native terminal and releases protection',
    () async {
      final original = handle;
      handle = (call) async {
        if (call.method == 'startExport') {
          state.addAll({
            'kind': 'export',
            'status': 'running',
            'stage': 'packing',
            'sequence': 1,
          });
          store.coordinator.requestCancel(store.coordinator.activeTask!);
          return Map.of(state);
        }
        return original(call);
      };
      await expectLater(export(), throwsA(isA<BackupCancelledException>()));
      expect(calls, contains('cancel'));
      expect(store.coordinator.isProtected, isFalse);
    },
  );

  test(
    'native committed success wins late cancellation and retains cleanup warnings',
    () async {
      final original = handle;
      handle = (call) async {
        final result = await original(call);
        if (call.method == 'startExport') {
          store.coordinator.requestCancel(store.coordinator.activeTask!);
        }
        if (call.method == 'release') {
          return {...state, 'cleanupPending': true};
        }
        return result;
      };
      expect((await export()).archiveBytes, 2048);
      expect(calls, isNot(contains('accept')));
      expect(store.coordinator.progress!.stage, BackupStage.completed);
    },
  );

  test(
    'phase byte counts restart without a false overall percentage',
    () async {
      final original = handle;
      var step = 0;
      final stages = <BackupStage>[];
      store.coordinator.addListener(() {
        if (store.coordinator.progress != null) {
          stages.add(store.coordinator.progress!.stage);
        }
      });
      handle = (call) async {
        if (call.method == 'startExport') {
          state['status'] = 'running';
          return Map.of(state);
        }
        if (call.method == 'snapshot' && step < 4) {
          state.addAll({
            'sequence': step + 1,
            'stage': ['preparing', 'packing', 'verifying', 'saving'][step],
            'processedBytes': 0,
            'totalBytes': 10,
          });
          step++;
          return Map.of(state);
        }
        if (call.method == 'snapshot' && step == 4) {
          step++;
          await original(const MethodCall('startExport'));
        }
        return original(call);
      };
      await export();
      expect(
        stages,
        containsAllInOrder([
          BackupStage.preparing,
          BackupStage.packing,
          BackupStage.verifying,
          BackupStage.saving,
          BackupStage.completed,
        ]),
      );
    },
  );

  test(
    'estimates keep 64-bit sizes, count local target copy separately and leave target capacity unknown',
    () {
      final recording = Recording(
        id: 'large',
        title: 'Large',
        filePath: '/private/large.aac',
        createdAt: now,
        duration: const Duration(seconds: 1),
        fileSizeBytes: 5 * 1024 * 1024 * 1024,
        format: RecordingFormat.aac,
      );
      final plan = BackupExportPlan.fromSnapshot(
        LibrarySnapshot([], [recording], {'large'}),
        now,
      );
      expect(
        plan.estimate.temporaryBytes,
        greaterThan(recording.fileSizeBytes),
      );
      expect(
        plan.estimate.combinedLocalBytes,
        plan.estimate.temporaryBytes * 2,
      );
      expect(plan.estimate.targetAvailableBytes, isNull);
      expect(plan.estimate.approximateReadBytes, recording.fileSizeBytes * 4);
    },
  );

  test(
    'invalid metadata rejects locally rather than generating a partial archive',
    () {
      final recording = Recording(
        id: '../bad',
        title: 'Bad',
        filePath: '/private/bad.aac',
        createdAt: now,
        duration: const Duration(seconds: 1),
        fileSizeBytes: 3,
        format: RecordingFormat.aac,
      );
      expect(
        () => BackupExportPlan.fromSnapshot(
          LibrarySnapshot([], [recording], {}),
          now,
        ),
        throwsA(isA<contract.BackupValidationException>()),
      );
    },
  );
}
