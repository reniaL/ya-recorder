import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ya_recorder/backup/backup_progress.dart';
import 'package:ya_recorder/backup/library_coordinator.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/recording/recording_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('backup-recording-gate');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late RecordingService service;
  late List<String> calls;
  late String state;
  late String? session;
  late bool writerBlocked;
  Completer<void>? startGate;

  setUp(() {
    service = RecordingService(commands: channel);
    calls = [];
    state = 'idle';
    session = null;
    writerBlocked = false;
    startGate = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'getStatus') {
        return {
          'state': state,
          'sessionId': session,
          'format': state == 'idle' && session == null ? null : 'aac',
          'elapsedMs': 0,
          'canResume': state == 'paused',
          'backupBlocked': writerBlocked,
        };
      }
      if (call.method == 'start') await startGate?.future;
      if (call.method == 'recoverRecordings') {
        return {'recordings': [], 'unresolvedCount': 0};
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<T> backup<T>(Future<T> Function(BackupLease) action) =>
      service.runBackup(
        taskId: 'task',
        operation: BackupOperation.export,
        action: action,
      );
  Future<void> tick() => Future<void>.delayed(Duration.zero);

  test(
    'actual native states block preparing, recording, paused, stopping and discarding',
    () async {
      for (final nativeState in [
        'preparing',
        'recording',
        'paused',
        'stopping',
        'discarding',
      ]) {
        state = nativeState;
        session = 'native-session';
        await expectLater(
          backup((_) async {}),
          throwsA(isA<LibraryBusyException>()),
        );
        expect(service.coordinator.isProtected, isFalse);
      }
      state = 'failed';
      await expectLater(
        backup((_) async {}),
        throwsA(isA<LibraryBusyException>()),
      );
      session = null;
      await backup((_) async {});
      state = 'idle';
      await backup((_) async {});
    },
  );

  test(
    'native start command remains a writer until the platform reply returns',
    () async {
      startGate = Completer<void>();
      final starting = service.start(format: RecordingFormat.aac);
      await tick();
      expect(calls, ['start']);
      await expectLater(
        backup((_) async {}),
        throwsA(isA<LibraryBusyException>()),
      );
      startGate!.complete();
      await starting;
      await backup((_) async {});
    },
  );

  test(
    'native writer lease blocks backup even when displayed state is idle',
    () async {
      writerBlocked = true;
      await expectLater(
        backup((_) async {}),
        throwsA(isA<LibraryBusyException>()),
      );
      writerBlocked = false;
      await backup((_) async {});
    },
  );

  test(
    'native recovery waits and direct start is rejected while backup owns library',
    () async {
      final release = Completer<void>();
      final task = backup((_) => release.future);
      await tick();
      final recovery = service.recoverRecordings();
      await expectLater(
        service.start(format: RecordingFormat.aac),
        throwsA(isA<LibraryBusyException>()),
      );
      await tick();
      expect(calls, ['getStatus']);
      release.complete();
      await task;
      expect((await recovery).recordings, isEmpty);
      expect(calls, ['getStatus', 'recoverRecordings']);
    },
  );
}
