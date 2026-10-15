import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ya_recorder/backup/backup_document_service.dart';
import 'package:ya_recorder/backup/library_coordinator.dart';
import 'package:ya_recorder/recording/recording_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const commands = MethodChannel('test/backup');
  const recordingCommands = MethodChannel('test/backup-recording');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late BackupDocumentService documents;
  late RecordingService recording;
  late Map<String, Object?> state;
  late List<String> calls;
  late Future<Object?> Function(MethodCall) handle;
  const document = BackupDocument(
    uri: 'content://provider/zip',
    displayName: 'test.zip',
  );

  setUp(() {
    documents = BackupDocumentService(
      commands: commands,
      pollInterval: Duration.zero,
    );
    recording = RecordingService(commands: recordingCommands);
    state = {
      'taskId': 'native-task',
      'sequence': 0,
      'status': 'prepared',
      'processedBytes': 0,
      'stagedPath': '/private/task/payload.zip',
    };
    calls = [];
    messenger.setMockMethodCallHandler(
      recordingCommands,
      (_) async => {
        'state': 'idle',
        'elapsedMs': 0,
        'canResume': false,
        'backupBlocked': false,
      },
    );
    handle = (call) async {
      switch (call.method) {
        case 'prepare':
          return Map.of(state);
        case 'startCopy':
          state.addAll({
            'status': 'completed',
            'sequence': 2,
            'processedBytes': 123,
          });
          return Map.of(state);
        case 'snapshot':
          return Map.of(state);
        case 'cancel':
          state.addAll({'status': 'cancelled', 'sequence': 3});
          return null;
        case 'release':
          return Map.of(state);
        default:
          return null;
      }
    };
    messenger.setMockMethodCallHandler(commands, (call) {
      calls.add(call.method);
      return handle(call);
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(commands, null);
    messenger.setMockMethodCallHandler(recordingCommands, null);
  });

  test('picker cancellation never prepares or protects data', () async {
    expect(await documents.pickSource(), isNull);
    expect(recording.coordinator.isProtected, isFalse);
    expect(calls, ['pickSource']);
  });

  test(
    'native transfer and cleanup hold the lease through consumption',
    () async {
      final original = handle;
      handle = (call) async {
        if (call.method == 'release') {
          expect(recording.coordinator.isProtected, isTrue);
        }
        return original(call);
      };
      final result = await documents.copy(
        recordingService: recording,
        document: document,
        write: false,
        consume: (value) async {
          expect(recording.coordinator.isProtected, isTrue);
          await expectLater(
            recording.coordinator.mutate(() async {}),
            throwsA(isA<LibraryBusyException>()),
          );
          expect(value.processedBytes, 123);
          return 'consumed';
        },
      );
      expect(result, 'consumed');
      expect(calls, contains('accept'));
      expect(recording.coordinator.isProtected, isFalse);
      expect(calls.last, 'release');
    },
  );

  test(
    'busy recording releases prepared files without starting service',
    () async {
      messenger.setMockMethodCallHandler(
        recordingCommands,
        (_) async => {
          'state': 'paused',
          'sessionId': 'recording',
          'format': 'aac',
          'elapsedMs': 10,
          'canResume': true,
        },
      );
      await expectLater(
        documents.copy(
          recordingService: recording,
          document: document,
          write: false,
          consume: (_) async {},
        ),
        throwsA(isA<LibraryBusyException>()),
      );
      expect(calls, isNot(contains('startCopy')));
      expect(calls.last, 'release');
    },
  );

  test(
    'cancel waits for native terminal state and cleanup before unlocking',
    () async {
      final original = handle;
      handle = (call) async {
        if (call.method == 'startCopy') {
          state['status'] = 'running';
          recording.coordinator.requestCancel(
            recording.coordinator.activeTask!,
          );
          return Map.of(state);
        }
        if (call.method == 'cancel' || call.method == 'release') {
          expect(recording.coordinator.isProtected, isTrue);
        }
        return original(call);
      };
      await expectLater(
        documents.copy(
          recordingService: recording,
          document: document,
          write: false,
          consume: (_) async => fail('cancelled transfer consumed'),
        ),
        throwsA(isA<BackupCancelledException>()),
      );
      expect(calls, contains('cancel'));
      expect(recording.coordinator.isProtected, isFalse);
    },
  );

  test('consume failure still cleans staged file inside protection', () async {
    await expectLater(
      documents.copy(
        recordingService: recording,
        document: document,
        write: false,
        consume: (_) async => throw const FormatException('bad zip'),
      ),
      throwsFormatException,
    );
    expect(calls.last, 'release');
    expect(recording.coordinator.lastError, isA<FormatException>());
    expect(calls, isNot(contains('accept')));
  });

  test('preparation failure cleans without starting transfer', () async {
    await expectLater(
      documents.copy(
        recordingService: recording,
        document: document,
        write: true,
        prepareOutput: (_) async => throw StateError('no space'),
        consume: (_) async {},
      ),
      throwsStateError,
    );
    expect(calls, isNot(contains('startCopy')));
    expect(calls.last, 'release');
  });

  test('service start failure never reports success', () async {
    final original = handle;
    handle = (call) async {
      if (call.method == 'startCopy') {
        state.addAll({'status': 'failed', 'error': 'service-start-failed'});
        return Map.of(state);
      }
      return original(call);
    };
    await expectLater(
      documents.copy(
        recordingService: recording,
        document: document,
        write: false,
        consume: (_) async => fail('failed transfer consumed'),
      ),
      throwsA(isA<BackupTransferException>()),
    );
    expect(recording.coordinator.lastResult, isNull);
  });

  test('undeletable target is retained in the error', () async {
    final original = handle;
    handle = (call) async {
      if (call.method == 'release') {
        return {...state, 'residualUri': document.uri};
      }
      return original(call);
    };
    await expectLater(
      documents.copy(
        recordingService: recording,
        document: document,
        write: true,
        consume: (_) async {},
      ),
      throwsA(
        isA<BackupTransferException>().having(
          (e) => e.snapshot.residualUri,
          'residualUri',
          document.uri,
        ),
      ),
    );
    expect(recording.coordinator.isProtected, isFalse);
  });

  test('new engine startup waits for surviving worker then cleans', () async {
    final barrier = Completer<void>();
    var snapshots = 0;
    final original = handle;
    handle = (call) async {
      if (call.method == 'snapshot') {
        snapshots++;
        if (snapshots == 1) return {...state, 'status': 'running'};
        await barrier.future;
        return {...state, 'status': 'interrupted'};
      }
      return original(call);
    };
    var wrote = false;
    final gate = LibraryCoordinator(
      recoverInterruptedTask: documents.recoverInterruptedTransfer,
    );
    final pending = gate.mutate(() async {
      wrote = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(wrote, isFalse);
    barrier.complete();
    await pending;
    expect(wrote, isTrue);
    expect(calls.last, 'release');
  });
}
