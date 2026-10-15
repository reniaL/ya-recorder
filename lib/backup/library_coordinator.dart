import 'dart:async';

import 'package:flutter/foundation.dart';

import 'backup_progress.dart';

class LibraryBusyException implements Exception {
  const LibraryBusyException();

  @override
  String toString() => 'LibraryBusyException: library data is protected';
}

class BackupCancelledException implements Exception {
  const BackupCancelledException();
}

/// A scoped capability; only its creating coordinator can authorize access.
class BackupLease {
  BackupLease._(this.taskId, this.operation);
  final String taskId;
  final BackupOperation operation;
  final _released = Completer<void>();
  final _cancelSignal = Completer<void>();
  BackupProgress? _progress;
  bool _closing = false;
  bool _cancelRequested = false;

  BackupProgress? get progress => _progress;
  bool get cancelRequested => _cancelRequested;
  Future<void> get whenCancelled => _cancelSignal.future;

  void checkCancelled() {
    if (_cancelRequested) throw const BackupCancelledException();
  }
}

/// One library, one coordinator, including all RecordingStore instances and
/// RecordingService callers that can modify it. No long SQLite transaction.
class LibraryCoordinator extends ChangeNotifier {
  LibraryCoordinator({Future<void> Function()? recoverInterruptedTask})
    : _recoverInterruptedTask = recoverInterruptedTask;

  final Future<void> Function()? _recoverInterruptedTask;
  Future<void>? _initialization;
  bool _initialized = false;
  int _writers = 0;
  BackupLease? _lease;
  final Set<Future<void>> _ownedAccess = {};
  Object? _ownedError;
  BackupProgress? _lastProgress;
  Object? _lastError;
  Object? _lastResult;

  bool get isProtected => _lease != null;
  bool get hasPendingWriters => _writers != 0;
  BackupLease? get activeTask => _lease;
  BackupProgress? get progress => _lease?.progress ?? _lastProgress;
  Object? get lastError => _lastError;
  Object? get lastResult => _lastResult;

  /// Future task-journal recovery must be supplied before normal app startup.
  /// Failure remains fail-closed and is retryable, never treated as recovered.
  Future<void> ensureInitialized() {
    if (_initialized) return Future.value();
    // Assign the shared future before invoking recovery, including sync throws.
    return _initialization ??= Future<void>.microtask(_initialize);
  }

  Future<void> _initialize() async {
    _writers++;
    try {
      await _recoverInterruptedTask?.call();
      _initialized = true;
    } finally {
      _writers--;
      _initialization = null;
    }
  }

  /// Admission is synchronous, before the first await. A backup cannot pass
  /// between permission approval and recording start, or an in-flight DB write.
  Future<T> mutate<T>(Future<T> Function() action) {
    if (isProtected) return Future.error(const LibraryBusyException());
    _writers++;
    return _finishMutation(action);
  }

  Future<T> _finishMutation<T>(Future<T> Function() action) async {
    try {
      await ensureInitialized();
      return await action();
    } finally {
      _writers--;
    }
  }

  /// Retain native save/recovery and cleanup work; never acknowledge or discard
  /// a READY draft merely because the library is temporarily protected.
  Future<T> deferMutation<T>(Future<T> Function() action) async {
    while (_lease != null) {
      await _lease!._released.future;
    }
    return mutate(action);
  }

  /// Reject rather than wait for accepted writes, so no queue/lock deadlock.
  /// The idle probe is mandatory, including after app reattachment to a native
  /// recording session. Errors release the reservation and remain fail-closed.
  Future<T> runBackup<T>({
    required String taskId,
    required BackupOperation operation,
    required Future<bool> Function() recordingIsIdle,
    required Future<T> Function(BackupLease lease) action,
  }) async {
    await ensureInitialized();
    if (taskId.isEmpty) throw ArgumentError.value(taskId, 'taskId');
    if (_lease != null || _writers != 0) throw const LibraryBusyException();
    final lease = BackupLease._(taskId, operation);
    _lease = lease;
    _lastError = null;
    _ownedError = null;
    _lastResult = null;
    _lastProgress = null;
    lease._progress = BackupProgress(
      taskId: taskId,
      sequence: 0,
      operation: operation,
      stage: operation == BackupOperation.export
          ? BackupStage.preparing
          : BackupStage.checking,
      processedBytes: 0,
      processedRecordings: 0,
    );
    notifyListeners();
    try {
      final idle = await Future.any<bool>([
        Future<bool>.sync(recordingIsIdle).timeout(const Duration(seconds: 10)),
        lease._cancelSignal.future.then<bool>(
          (_) => throw const BackupCancelledException(),
        ),
      ]);
      if (!idle) throw const LibraryBusyException();
      lease.checkCancelled();
      final result = await action(lease);
      lease._closing = true;
      await _drainOwnedAccess();
      if (_ownedError != null) throw _ownedError!;
      _lastResult = result;
      _terminal(lease, BackupStage.completed);
      return result;
    } catch (error) {
      _lastError = error;
      _terminal(
        lease,
        error is BackupCancelledException
            ? BackupStage.cancelled
            : BackupStage.failed,
      );
      rethrow;
    } finally {
      lease._closing = true;
      // Unawaited authorized IO must finish before deferred writers resume.
      await _drainOwnedAccess();
      _lastProgress = lease.progress;
      _lease = null;
      lease._released.complete();
      notifyListeners();
    }
  }

  Future<void> _drainOwnedAccess() async {
    while (_ownedAccess.isNotEmpty) {
      await Future.wait(_ownedAccess.toList());
    }
  }

  void _terminal(BackupLease lease, BackupStage stage) {
    final prior = lease.progress!;
    lease._progress = BackupProgress(
      taskId: lease.taskId,
      sequence: prior.sequence + 1,
      operation: lease.operation,
      stage: stage,
      processedBytes: prior.processedBytes,
      totalBytes: prior.totalBytes,
      processedRecordings: prior.processedRecordings,
      totalRecordings: prior.totalRecordings,
    );
  }

  void requireLease(BackupLease lease) {
    if (!identical(_lease, lease) || lease._closing) {
      throw const LibraryBusyException();
    }
  }

  /// Only a current task capability can enter private backup storage APIs.
  /// This does not disable the guard on ordinary public mutation methods.
  Future<T> ownedAccess<T>(BackupLease lease, Future<T> Function() action) {
    requireLease(lease);
    final result = Future<T>.sync(action);
    late final Future<void> settled;
    settled = result
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace _) {
            _ownedError ??= error;
          },
        )
        .whenComplete(() => _ownedAccess.remove(settled));
    _ownedAccess.add(settled);
    return result;
  }

  void report(BackupLease lease, BackupProgress value) {
    requireLease(lease);
    if (value.taskId != lease.taskId ||
        value.operation != lease.operation ||
        value.sequence <= (lease.progress?.sequence ?? -1)) {
      throw ArgumentError('Stale or mismatched task progress');
    }
    lease._progress = value;
    notifyListeners();
  }

  void requestCancel(BackupLease lease) {
    requireLease(lease);
    if (lease.progress?.canCancel ?? true) {
      lease._cancelRequested = true;
      if (!lease._cancelSignal.isCompleted) lease._cancelSignal.complete();
      notifyListeners();
    }
  }
}
