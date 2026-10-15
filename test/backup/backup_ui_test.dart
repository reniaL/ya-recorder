import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/backup/backup_controller.dart';
import 'package:ya_recorder/backup/backup_contract.dart' as contract;
import 'package:ya_recorder/backup/backup_document_service.dart';
import 'package:ya_recorder/backup/backup_page.dart';
import 'package:ya_recorder/backup/library_coordinator.dart';
import 'package:ya_recorder/backup/backup_progress.dart';
import 'package:ya_recorder/l10n/localization.dart';
import 'package:ya_recorder/recording/recording_service.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/settings/app_language.dart';
import 'package:ya_recorder/settings/recording_settings_page.dart';
import 'package:ya_recorder/storage/recording_store.dart';
import 'package:ya_recorder/storage/folder_scope_picker.dart';
import 'package:ya_recorder/storage/recently_deleted_page.dart';

import 'backup_fixture.dart';

class _SettingsStore extends RecordingStore {
  _SettingsStore()
    : super(
        databasePath: 'unused-backup-ui-settings',
        databaseFactory: databaseFactoryFfi,
      );
  @override
  Future<ThemeMode> getThemeMode() async => ThemeMode.system;
  @override
  Future<AppLanguage> getAppLanguage() async => AppLanguage.english;
  @override
  Future<RecordingFormat> getDefaultRecordingFormat() async =>
      RecordingFormat.aac;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  const commands = MethodChannel('test/backup-ui');
  const recorderCommands = MethodChannel('test/backup-ui-recording');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late RecordingStore store;
  late BackupController controller;
  late RecordingService recording;
  late Map<String, Object?> state;
  late List<String> calls;
  late bool pickerCancelled;
  late bool holdExport;
  late String? exportError;
  late ShareResultStatus shareStatus;
  late ShareParams? shared;
  late BackupFixture fixture;
  late String? pendingOpen;

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue, reason: 'asynchronous workflow did not settle');
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('backup-ui-');
    await Directory(path.join(directory.path, 'recordings')).create();
    store = RecordingStore(
      databasePath: path.join(directory.path, 'index.db'),
      databaseFactory: databaseFactoryFfi,
    );
    await store.open();
    recording = RecordingService(commands: recorderCommands);
    calls = [];
    pickerCancelled = false;
    holdExport = false;
    exportError = null;
    shareStatus = ShareResultStatus.success;
    shared = null;
    fixture = BackupFixture();
    pendingOpen = null;
    state = {
      'taskId': '11111111-1111-4111-8111-111111111111',
      'sequence': 0,
      'status': 'prepared',
      'processedBytes': 0,
      'stagedPath': path.join(directory.path, 'payload.zip'),
    };
    messenger.setMockMethodCallHandler(
      recorderCommands,
      (call) async => switch (call.method) {
        'getAvailableFormats' => ['aac', 'mp3'],
        'setAppLanguage' => null,
        _ => {'state': 'idle', 'elapsedMs': 0, 'canResume': false},
      },
    );
    messenger.setMockMethodCallHandler(commands, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'pickSource':
        case 'pickTarget':
          return pickerCancelled
              ? null
              : {'uri': 'content://provider/backup', 'displayName': 'test.zip'};
        case 'prepare':
          state['status'] = 'prepared';
          return Map.of(state);
        case 'startExport':
          if (exportError != null) {
            state.addAll({'status': 'failed', 'errorDetail': exportError});
          } else {
            await File(
              path.join(directory.path, 'payload.zip'),
            ).writeAsBytes([1, 2, 3]);
            state.addAll({
              'kind': 'export',
              'accepted': !holdExport,
              'status': holdExport ? 'running' : 'completed',
              'stage': 'packing',
              'processedBytes': 1,
              'totalBytes': 3,
              'cachedArchivePath': path.join(directory.path, 'payload.zip'),
              'retainedUntilMs': DateTime.now()
                  .add(const Duration(hours: 24))
                  .millisecondsSinceEpoch,
            });
          }
          return Map.of(state);
        case 'startImport':
          fixture.assemble();
          final content = {
            'manifest.json': fixture.manifestBytes,
            'metadata.json': fixture.metadataBytes,
            ...fixture.audio,
          };
          await File(path.join(directory.path, 'verified.json')).writeAsString(
            jsonEncode({
              'manifest': utf8.decode(fixture.manifestBytes),
              'metadata': utf8.decode(fixture.metadataBytes),
              'entries': [
                for (final e in content.entries)
                  {
                    'path': e.key,
                    'size': e.value.length,
                    'sha256': sha256.convert(e.value).toString(),
                  },
              ],
            }),
          );
          state.addAll({'status': 'completed', 'kind': 'import'});
          return Map.of(state);
        case 'placeImport':
          for (final f in (call.arguments as Map)['files'] as List) {
            await File(f['target'] as String).writeAsBytes([1, 2, 3]);
          }
          state['status'] = 'completed';
          return Map.of(state);
        case 'snapshot':
          return Map.of(state);
        case 'cancel':
          state['status'] = 'cancelled';
          return null;
        case 'recordImportSummary':
          state.addAll({
            'importSummaryKnown': true,
            'recordingCount': (call.arguments as Map)['recordings'],
            'folderCount': (call.arguments as Map)['folders'],
            'duplicateCount': (call.arguments as Map)['duplicates'],
            'conflictCount': (call.arguments as Map)['conflicts'],
          });
          return null;
        case 'accept':
          return null;
        case 'release':
          return Map.of(state);
        case 'takeOpenTask':
          final id = pendingOpen;
          pendingOpen = null;
          return id;
        default:
          throw StateError('Unexpected ${call.method}');
      }
    });
    controller = BackupController(
      store: store,
      recordingService: recording,
      documents: BackupDocumentService(
        commands: commands,
        pollInterval: const Duration(milliseconds: 5),
      ),
      share: (params) async {
        shared = params;
        return ShareResult('', shareStatus);
      },
    );
  });

  tearDown(() async {
    controller.dispose();
    messenger.setMockMethodCallHandler(commands, null);
    messenger.setMockMethodCallHandler(recorderCommands, null);
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<void> open(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    bool scaled = false,
    bool route = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: ThemeData(brightness: brightness),
        builder: scaled
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              )
            : null,
        home: route
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    key: const Key('openBackup'),
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BackupPage(controller: controller),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              )
            : BackupPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    if (route) {
      await tester.tap(find.byKey(const Key('openBackup')));
      await tester.pumpAndSettle();
    }
  }

  test(
    'file picker cancellation never acquires protection or starts native work',
    () async {
      pickerCancelled = true;
      await controller.startImport();
      await controller.reviewExport();
      await controller.startExport();
      expect(calls, ['pickSource', 'pickTarget']);
      expect(controller.coordinator.isProtected, isFalse);
      expect(controller.exportReview, isNotNull);
    },
  );

  test(
    'failure classification hides raw diagnostics behind translated categories',
    () {
      expect(
        classifyBackupFailure(const LibraryBusyException()),
        BackupFailure.busy,
      );
      expect(
        classifyBackupFailure(
          const contract.BackupValidationException(
            contract.BackupErrorCode.unsupportedVersion,
            'private-path',
          ),
        ),
        BackupFailure.version,
      );
      for (final entry in {
        'zip64-unsupported': BackupFailure.zip64,
        'insufficient-space': BackupFailure.space,
        'document-permission-denied': BackupFailure.permission,
        'Local audio unavailable': BackupFailure.local,
        'process-interrupted': BackupFailure.interrupted,
      }.entries) {
        expect(classifyBackupFailure(StateError(entry.key)), entry.value);
      }
      expect(
        BackupController.suggestedName(DateTime(2026, 10, 15, 8, 9, 7)),
        '丫丫录音备份-20261015-080907.zip',
      );
    },
  );

  testWidgets(
    'export review explains scope, encryption and separate temporary space',
    (tester) async {
      await open(tester);
      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('exportBackup'))),
      );
      await tester.runAsync(() => until(() => controller.exportReview != null));
      await tester.pumpAndSettle();
      expect(find.text('Review export'), findsOneWidget);
      expect(find.textContaining('not encrypted'), findsOneWidget);
      expect(find.textContaining('temporary ZIP'), findsOneWidget);
      expect(store.coordinator.isProtected, isFalse);
      await tester.scrollUntilVisible(
        find.byKey(const Key('dismissBackupReview')),
        220,
      );
      await tester.tap(find.byKey(const Key('dismissBackupReview')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exportBackup')), findsOneWidget);
    },
  );

  testWidgets(
    'back and re-entry preserve import confirmation, data protection and final result',
    (tester) async {
      await open(tester, route: true);
      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('importBackup'))),
      );
      await tester.runAsync(
        () => until(() => controller.importPreview != null),
      );
      await tester.pumpAndSettle();
      expect(store.coordinator.isProtected, isTrue);
      expect(find.text('Review import'), findsOneWidget);
      expect(await tester.runAsync(() => store.listRecordings()), isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(controller.importPreview, isNotNull);
      expect(store.coordinator.isProtected, isTrue);
      await tester.tap(find.byKey(const Key('openBackup')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('confirmBackupImport')),
        220,
      );
      await tester.tap(find.byKey(const Key('confirmBackupImport')));
      await tester.runAsync(() => until(() => controller.outcome != null));
      await tester.pumpAndSettle();
      expect(find.text('Import complete'), findsOneWidget);
      expect((await tester.runAsync(() => store.listRecordings()))!.length, 3);
      expect(store.coordinator.isProtected, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('openBackup')));
      await tester.pumpAndSettle();
      expect(find.text('Import complete'), findsOneWidget);
    },
  );

  testWidgets(
    'confirmation cancellation returns a cancelled result and no library writes',
    (tester) async {
      await open(tester);
      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('importBackup'))),
      );
      await tester.runAsync(
        () => until(() => controller.importPreview != null),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('cancelBackupTask')),
        220,
      );
      await tester.tap(find.byKey(const Key('cancelBackupTask')));
      await tester.runAsync(() => until(() => !controller.busy));
      await tester.pumpAndSettle();
      expect(controller.outcome, BackupOutcome.cancelled);
      expect(await tester.runAsync(() => store.listRecordings()), isEmpty);
      expect(calls, isNot(contains('placeImport')));
    },
  );

  testWidgets(
    'language and theme changes keep the same waiting task and translate it',
    (tester) async {
      await tester.runAsync(() async {
        unawaited(controller.startImport());
        await until(() => controller.importPreview != null);
      });
      final lease = store.coordinator.activeTask;
      await open(tester);
      expect(find.text('Review import'), findsOneWidget);
      await open(
        tester,
        locale: const Locale('zh'),
        brightness: Brightness.dark,
      );
      expect(find.text('导入预览'), findsOneWidget);
      expect(store.coordinator.activeTask, same(lease));
      await tester.runAsync(() async {
        controller.cancel();
        await until(() => !controller.busy);
      });
      await tester.pumpAndSettle();
      expect(find.text('任务已取消，已有录音保持不变。'), findsOneWidget);
    },
  );

  testWidgets(
    'native progress remains active after leaving and cancel drains the task',
    (tester) async {
      holdExport = true;
      await tester.runAsync(() => controller.reviewExport());
      await open(tester, route: true);
      await tester.runAsync(
        () => tester.tap(find.byKey(const Key('saveBackup'))),
      );
      await tester.runAsync(() => until(() => calls.contains('startExport')));
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('Packing files'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(store.coordinator.isProtected, isTrue);
      await tester.tap(find.byKey(const Key('openBackup')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('cancelBackupTask')),
        220,
      );
      await tester.tap(find.byKey(const Key('cancelBackupTask')));
      await tester.runAsync(() => until(() => !controller.busy));
      await tester.pumpAndSettle();
      expect(controller.outcome, BackupOutcome.cancelled);
      expect(calls, contains('release'));
    },
  );

  test(
    'sharing uses application/zip, preserves the retained file and reports only handoff',
    () async {
      await controller.reviewExport();
      await controller.startExport();
      await controller.shareExport();
      expect(shared!.files!.single.mimeType, 'application/zip');
      expect(shared!.fileNameOverrides, ['test.zip']);
      expect(
        await File(controller.exported!.cachedArchivePath!).exists(),
        isTrue,
      );
      expect(controller.shareHandedOff, isTrue);
      shareStatus = ShareResultStatus.dismissed;
      await controller.shareExport();
      expect(controller.shareHandedOff, isFalse);
      expect(controller.shareFailed, isFalse);
      await File(controller.exported!.cachedArchivePath!).delete();
      await controller.shareExport();
      expect(controller.shareFailed, isTrue);
      expect(controller.outcome, BackupOutcome.exported);
    },
  );

  test(
    'notification requests match current task and restore native successful export receipt',
    () async {
      state.addAll({
        'kind': 'export',
        'accepted': true,
        'status': 'completed',
        'uri': 'content://saved',
        'displayName': 'saved.zip',
        'recordingCount': 5,
        'folderCount': 2,
      });
      pendingOpen = state['taskId'] as String;
      var opened = 0;
      controller.onOpenRequested = () => opened++;
      await controller.initialize();
      expect(opened, 1);
      expect(controller.exported!.recordingCount, 5);
      expect(controller.exported!.document.displayName, 'saved.zip');
      Future<void> nativeOpen(String id) async {
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          commands.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('openTask', id),
          ),
          (_) => done.complete(),
        );
        await done.future;
      }

      await nativeOpen('old-task');
      expect(opened, 1);
      await nativeOpen(state['taskId'] as String);
      expect(opened, 2);
    },
  );

  testWidgets(
    'settings retains current task entry without owning its lifecycle',
    (tester) async {
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: RecordingSettingsPage(
              store: _SettingsStore(),
              service: recording,
              backupController: controller,
              onOpenBackup: () {},
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await store.open();
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backupSettings')), findsOneWidget);
      await tester.runAsync(() async {
        unawaited(controller.startImport());
        await until(() => controller.importPreview != null);
      });
      await tester.pumpAndSettle();
      expect(find.text('View current task'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(store.coordinator.isProtected, isTrue);
      await tester.runAsync(() async {
        controller.cancel();
        await until(() => !controller.busy);
      });
    },
  );

  test(
    'database-authoritative recovered import restores counts without treating preview as committed',
    () async {
      state.addAll({
        'kind': 'import',
        'status': 'interrupted',
        'accepted': false,
        'importSummaryKnown': true,
        'recordingCount': 2,
        'folderCount': 1,
        'duplicateCount': 3,
        'conflictCount': 4,
      });
      await controller.initialize();
      expect(controller.outcome, BackupOutcome.interrupted);
      expect(controller.restoredImportSummary, isNull);
      store.coordinator.recoveredImportTaskId = state['taskId'] as String;
      store.coordinator.recoveredImportCommitted = true;
      await controller.initialize();
      expect(controller.outcome, BackupOutcome.recoveredImport);
      expect(controller.restoredImportSummary!.recordings, 2);
      expect(controller.restoredImportSummary!.conflicts, 4);
    },
  );

  test('a late startup receipt cannot replace a newer workflow', () async {
    final receipt = Completer<Map<String, Object?>>();
    messenger.setMockMethodCallHandler(
      commands,
      (call) async => call.method == 'snapshot' ? receipt.future : null,
    );
    final initialization = controller.initialize();
    await controller.reviewExport();
    receipt.complete({
      ...state,
      'kind': 'export',
      'accepted': true,
      'status': 'completed',
    });
    await initialization;
    expect(controller.exportReview, isNotNull);
    expect(controller.exported, isNull);
    expect(controller.outcome, isNull);
  });

  test(
    'a new picker failure clears prior result details and never exposes its diagnostic path',
    () async {
      await controller.reviewExport();
      await controller.startExport();
      expect(controller.exported, isNotNull);
      messenger.setMockMethodCallHandler(
        commands,
        (_) async => throw PlatformException(
          code: 'document-permission-denied',
          message: '/private/secret',
        ),
      );
      await controller.startImport();
      expect(controller.outcome, BackupOutcome.failed);
      expect(controller.failure, BackupFailure.permission);
      expect(controller.exported, isNull);
    },
  );

  testWidgets(
    'startup recovery failure is reviewable and retryable without enabling new tasks',
    (tester) async {
      var fail = true;
      final coordinator = LibraryCoordinator(
        recoverInterruptedTask: () async {
          if (fail) throw StateError('ambiguous ownership');
        },
      );
      final isolatedStore = RecordingStore(
        databasePath: path.join(directory.path, 'blocked.db'),
        databaseFactory: databaseFactoryFfi,
        libraryCoordinator: coordinator,
      );
      final blocked = BackupController(
        store: isolatedStore,
        recordingService: RecordingService(commands: recorderCommands),
        documents: controller.documents,
      );
      try {
        await expectLater(coordinator.ensureInitialized(), throwsStateError);
        blocked.showStartupFailure(StateError('ambiguous ownership'));
        await tester.pumpWidget(
          MaterialApp(home: BackupPage(controller: blocked)),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('importBackup')),
          220,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('importBackup')))
              .onPressed,
          isNull,
        );
        fail = false;
        await tester.runAsync(() => blocked.retryRecovery());
        await tester.pumpAndSettle();
        expect(blocked.startupFailure, isFalse);
        await tester.scrollUntilVisible(
          find.byKey(const Key('importBackup')),
          220,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('importBackup')))
              .onPressed,
          isNotNull,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        blocked.dispose();
        await isolatedStore.close();
      }
    },
  );

  testWidgets('commit phase explains that cancellation is unavailable', (
    tester,
  ) async {
    final release = Completer<void>();
    final task = store.coordinator.runBackup(
      taskId: 'commit-ui',
      operation: BackupOperation.import,
      recordingIsIdle: () async => true,
      action: (lease) async {
        store.coordinator.report(
          lease,
          BackupProgress(
            taskId: lease.taskId,
            sequence: 1,
            operation: lease.operation,
            stage: BackupStage.committing,
            processedBytes: 0,
            processedRecordings: 0,
          ),
        );
        await release.future;
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: BackupPage(controller: controller)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(
      find.byKey(const Key('cancelBackupTask')),
      200,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cancelBackupTask')))
          .onPressed,
      isNull,
    );
    expect(find.text('正在完成导入，暂不可取消'), findsOneWidget);
    release.complete();
    await task;
    await tester.pumpAndSettle();
  });

  testWidgets('preview exposes folder renames in a scrollable sheet', (
    tester,
  ) async {
    await tester.runAsync(
      () => store.createFolder(id: 'local-empty', name: 'Empty folder'),
    );
    await tester.runAsync(() async {
      unawaited(controller.startImport());
      await until(() => controller.importPreview != null);
    });
    await open(tester);
    await tester.scrollUntilVisible(
      find.text('Folder names changed for import'),
      200,
    );
    await tester.tap(find.text('Folder names changed for import'));
    await tester.pumpAndSettle();
    expect(find.text('Empty folder（导入）'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      controller.cancel();
      await until(() => !controller.busy);
    });
  });

  testWidgets('fully duplicated empty folders show a no-additions result', (
    tester,
  ) async {
    fixture = BackupFixture(empty: true)..assemble();
    await tester.runAsync(() async {
      for (final f in fixture.parse().folders) {
        await store.createFolder(id: f.id, name: f.name);
      }
    });
    await tester.runAsync(() async {
      unawaited(controller.startImport());
      await until(() => controller.importPreview != null);
      controller.confirmImport();
      await until(() => !controller.busy);
    });
    await open(tester);
    await tester.scrollUntilVisible(
      find.text(
        'Everything already exists. No recordings or folders were added.',
      ),
      200,
    );
    expect(
      find.text(
        'Everything already exists. No recordings or folders were added.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'open folder selector refreshes imported folders after task release',
    (tester) async {
      await tester.runAsync(() async {
        unawaited(controller.startImport());
        await until(() => controller.importPreview != null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FolderScopePicker(store: store)),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle();
      expect(find.text('Empty folder'), findsNothing);
      await tester.runAsync(() async {
        controller.confirmImport();
        await until(() => !controller.busy);
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.text('Empty folder'), findsOneWidget);
    },
  );

  testWidgets(
    'recently deleted remains readable during protection and explains disabled changes',
    (tester) async {
      await tester.runAsync(() async {
        unawaited(controller.startImport());
        await until(() => controller.importPreview != null);
      });
      await tester.pumpWidget(
        MaterialApp(home: RecentlyDeletedPage(store: store)),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('备份任务正在保护'), findsOneWidget);
      expect(find.text('正在加载最近删除'), findsNothing);
      await tester.runAsync(() async {
        controller.cancel();
        await until(() => !controller.busy);
      });
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${locale.languageCode} backup screens fit 320px and 2x text in $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          await open(
            tester,
            locale: locale,
            brightness: brightness,
            scaled: true,
          );
          await tester.scrollUntilVisible(
            find.byKey(const Key('exportBackup')),
            220,
          );
          expect(
            tester.getSize(find.byKey(const Key('exportBackup'))).height,
            greaterThanOrEqualTo(48),
          );
          expect(
            tester.getSemantics(find.byKey(const Key('exportBackup'))).label,
            isNotEmpty,
          );
          await tester.runAsync(() => controller.reviewExport());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          controller.dismissReview();
          await tester.runAsync(() async {
            unawaited(controller.startImport());
            await until(() => controller.importPreview != null);
          });
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const Key('confirmBackupImport')),
            220,
          );
          expect(
            tester.getSize(find.byKey(const Key('confirmBackupImport'))).height,
            greaterThanOrEqualTo(48),
          );
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            controller.cancel();
            await until(() => !controller.busy);
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
}
