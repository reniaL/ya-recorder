import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ya_recorder/backup/backup_progress.dart';
import 'package:ya_recorder/backup/library_coordinator.dart';

void main() {
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  Future<T> backup<T>(
    LibraryCoordinator gate,
    Future<T> Function(BackupLease) action, {
    Future<bool> Function()? probe,
  }) => gate.runBackup(
    taskId: 'task',
    operation: BackupOperation.export,
    recordingIsIdle: probe ?? () async => true,
    action: action,
  );

  test(
    'reservation protects data during native probe; second task rejected',
    () async {
      final gate = LibraryCoordinator();
      final probe = Completer<bool>();
      var called = false;
      final task = backup(gate, (_) async {
        called = true;
      }, probe: () => probe.future);
      await tick();
      expect(gate.isProtected, isTrue);
      await expectLater(
        gate.mutate(() async {}),
        throwsA(isA<LibraryBusyException>()),
      );
      await expectLater(
        backup(gate, (_) async {}),
        throwsA(isA<LibraryBusyException>()),
      );
      probe.complete(true);
      await task;
      expect(called, isTrue);
      expect(gate.isProtected, isFalse);
      expect(gate.progress!.stage, BackupStage.completed);
    },
  );

  test(
    'accepted writes and delayed permission/start prevent task admission',
    () async {
      final gate = LibraryCoordinator();
      final permission = Completer<void>();
      final write = gate.mutate(() => permission.future);
      await expectLater(
        backup(gate, (_) async {}),
        throwsA(isA<LibraryBusyException>()),
      );
      permission.complete();
      await write;
      expect(await backup(gate, (_) async => 42), 42);
      expect(gate.lastResult, 42);
    },
  );

  test(
    'cancel during native status probe releases reservation without running action',
    () async {
      final gate = LibraryCoordinator();
      final nativeProbe = Completer<bool>();
      var ran = false;
      final task = backup(gate, (_) async {
        ran = true;
      }, probe: () => nativeProbe.future);
      await tick();
      final assertion = expectLater(
        task,
        throwsA(isA<BackupCancelledException>()),
      );
      gate.requestCancel(gate.activeTask!);
      await assertion;
      expect(gate.isProtected, isFalse);
      expect(ran, isFalse);
      nativeProbe.complete(true);
      await gate.mutate(() async {});
    },
  );

  test(
    'active native session and unavailable status fail closed and release',
    () async {
      final gate = LibraryCoordinator();
      await expectLater(
        backup(gate, (_) async {}, probe: () async => false),
        throwsA(isA<LibraryBusyException>()),
      );
      expect(gate.isProtected, isFalse);
      await expectLater(
        backup(
          gate,
          (_) async {},
          probe: () async => throw StateError('bridge'),
        ),
        throwsStateError,
      );
      expect(gate.isProtected, isFalse);
      expect(gate.progress!.stage, BackupStage.failed);
      await gate.mutate(() async {});
    },
  );

  test(
    'deferred work survives failure, cancellation and immediately following task',
    () async {
      final gate = LibraryCoordinator();
      final release = Completer<void>();
      var writes = 0;
      final task = backup(gate, (lease) async {
        await release.future;
        lease.checkCancelled();
      });
      await tick();
      final deferred = gate.deferMutation(() async => writes++);
      await tick();
      expect(writes, 0);
      gate.requestCancel(gate.activeTask!);
      final assertion = expectLater(
        task,
        throwsA(isA<BackupCancelledException>()),
      );
      release.complete();
      await assertion;
      await deferred;
      expect(writes, 1);
      expect(gate.progress!.stage, BackupStage.cancelled);
      await backup(gate, (_) async {});
      expect(gate.isProtected, isFalse);
    },
  );

  test(
    'revoked and foreign capabilities cannot authorize data access',
    () async {
      final gate = LibraryCoordinator();
      final other = LibraryCoordinator();
      late BackupLease revoked;
      await backup(gate, (lease) async {
        revoked = lease;
        expect(
          () => other.ownedAccess(lease, () async {}),
          throwsA(isA<LibraryBusyException>()),
        );
        await gate.ownedAccess(lease, () async {});
        await expectLater(
          gate.mutate(() async {}),
          throwsA(isA<LibraryBusyException>()),
        );
      });
      expect(
        () => gate.ownedAccess(revoked, () async {}),
        throwsA(isA<LibraryBusyException>()),
      );
    },
  );

  test(
    'task cannot unlock while authorized asynchronous storage is still in flight',
    () async {
      final gate = LibraryCoordinator();
      final io = Completer<void>();
      late Future<void> owned;
      final task = backup(gate, (lease) async {
        owned = gate.ownedAccess(lease, () => io.future);
      });
      await tick();
      expect(gate.isProtected, isTrue);
      expect(gate.progress!.stage, isNot(BackupStage.completed));
      var resumed = false;
      final writer = gate.deferMutation(() async {
        resumed = true;
      });
      io.complete();
      await owned;
      await task;
      await writer;
      expect(resumed, isTrue);
    },
  );

  test('owned failure cannot be misreported as task success', () async {
    final gate = LibraryCoordinator();
    await expectLater(
      backup(gate, (lease) async {
        try {
          await gate.ownedAccess(lease, () async => throw StateError('IO'));
        } catch (_) {
          /* The owner still records the storage failure. */
        }
      }),
      throwsStateError,
    );
    expect(gate.progress!.stage, BackupStage.failed);
    expect(gate.isProtected, isFalse);
  });

  test(
    'startup barrier serializes recovery before writers and retries failures',
    () async {
      final recovery = Completer<void>();
      var initialized = false;
      var wrote = false;
      final gate = LibraryCoordinator(
        recoverInterruptedTask: () async {
          await recovery.future;
          initialized = true;
        },
      );
      final write = gate.mutate(() async {
        expect(initialized, isTrue);
        wrote = true;
      });
      await tick();
      expect(wrote, isFalse);
      recovery.complete();
      await write;
      var attempts = 0;
      final retry = LibraryCoordinator(
        recoverInterruptedTask: () async {
          if (++attempts == 1) throw StateError('journal');
        },
      );
      await expectLater(backup(retry, (_) async {}), throwsStateError);
      expect(retry.isProtected, isFalse);
      await backup(retry, (_) async {});
      expect(attempts, 2);
    },
  );

  test(
    'progress rejects stale events; commit and terminal states refuse cancellation',
    () async {
      final gate = LibraryCoordinator();
      await backup(gate, (lease) async {
        final value = BackupProgress(
          taskId: lease.taskId,
          sequence: 1,
          operation: lease.operation,
          stage: BackupStage.committing,
          processedBytes: 3,
          totalBytes: 3,
          processedRecordings: 1,
        );
        gate.report(lease, value);
        expect(() => gate.report(lease, value), throwsArgumentError);
        gate.requestCancel(lease);
        expect(lease.cancelRequested, isFalse);
      });
      expect(gate.progress!.stage, BackupStage.completed);
    },
  );
}
