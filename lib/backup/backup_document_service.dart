import 'dart:async';

import 'package:flutter/services.dart';

import '../recording/recording_service.dart';
import 'backup_progress.dart';
import 'library_coordinator.dart';

class BackupDocument {
  const BackupDocument({required this.uri, required this.displayName});
  final String uri;
  final String displayName;

  factory BackupDocument.fromMap(Map<Object?, Object?> map) => BackupDocument(
    uri: map['uri']! as String,
    displayName: map['displayName']! as String,
  );
}

/// Native snapshots are also the event stream: each poll starts with current
/// state, so reattachment cannot miss completion between subscribe and query.
class BackupTransferSnapshot {
  BackupTransferSnapshot.fromMap(Map<Object?, Object?> map)
    : taskId = map['taskId']! as String,
      sequence = map['sequence']! as int,
      status = map['status']! as String,
      processedBytes = map['processedBytes']! as int,
      stagedPath = map['stagedPath']! as String,
      error = map['error'] as String?,
      errorDetail = map['errorDetail'] as String?,
      stage = map['stage'] as String?,
      exportCommitted = map['kind'] == 'export' && map['accepted'] == true,
      cachedArchivePath = map['cachedArchivePath'] as String?,
      retainedUntilMs = map['retainedUntilMs'] as int?,
      processedRecordings = map['processedRecordings'] as int? ?? 0,
      totalBytes = map['totalBytes'] as int?,
      cancelRequested = map['cancelRequested'] == true,
      residualUri = map['residualUri'] as String?,
      cleanupPending = map['cleanupPending'] == true,
      kind = map['kind'] as String?,
      accepted = map['accepted'] == true,
      uri = map['uri'] as String?,
      displayName = map['displayName'] as String?,
      recordingCount = map['recordingCount'] as int? ?? 0,
      folderCount = map['folderCount'] as int? ?? 0,
      duplicateCount = map['duplicateCount'] as int? ?? 0,
      conflictCount = map['conflictCount'] as int? ?? 0,
      importSummaryKnown = map['importSummaryKnown'] == true;

  final String taskId;
  final int sequence;
  final String status;
  final int processedBytes;
  final String stagedPath;
  final String? error;
  final String? errorDetail;
  final String? stage;
  final bool exportCommitted;
  final String? cachedArchivePath;
  final int? retainedUntilMs;
  final int processedRecordings;
  final int? totalBytes;
  final bool cancelRequested;
  final String? residualUri;
  final bool cleanupPending;
  bool get isRunning => status == 'running';

  // Optional receipt fields from the process-owned native journal.
  final String? kind;
  final bool accepted;
  final String? uri;
  final String? displayName;
  final int recordingCount;
  final int folderCount;
  final int duplicateCount;
  final int conflictCount;
  final bool importSummaryKnown;
}

class BackupTransferException implements Exception {
  const BackupTransferException(this.snapshot);
  final BackupTransferSnapshot snapshot;
  @override
  String toString() =>
      'BackupTransferException: ${snapshot.error ?? snapshot.status}'
      '${snapshot.errorDetail == null ? '' : '; ${snapshot.errorDetail}'}'
      '${snapshot.residualUri == null ? '' : '; residual: ${snapshot.residualUri}'}';
}

class BackupDocumentService {
  BackupDocumentService({
    MethodChannel? commands,
    this.pollInterval = const Duration(milliseconds: 250),
  }) : _commands =
           commands ??
           const MethodChannel('io.github.renial.ya_recorder/backup_commands');

  final MethodChannel _commands;
  final Duration pollInterval;

  void setOpenTaskHandler(Future<void> Function(String taskId)? handler) {
    _commands.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              if (call.method == 'openTask' && call.arguments is String) {
                await handler(call.arguments as String);
              }
            },
    );
  }

  Future<String?> takeOpenTask() =>
      _commands.invokeMethod<String>('takeOpenTask');

  Future<void> recordImportSummary(
    BackupLease lease, {
    required int recordings,
    required int folders,
    required int duplicates,
    required int conflicts,
  }) => _commands.invokeMethod<void>('recordImportSummary', {
    'taskId': lease.taskId,
    'recordings': recordings,
    'folders': folders,
    'duplicates': duplicates,
    'conflicts': conflicts,
  });

  Future<BackupDocument?> pickSource() => _pick('pickSource');
  Future<BackupDocument?> pickTarget(String name) =>
      _pick('pickTarget', {'name': name});

  Future<BackupDocument?> _pick(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    final value = await _commands.invokeMapMethod<Object?, Object?>(
      method,
      args,
    );
    return value == null ? null : BackupDocument.fromMap(value);
  }

  Future<BackupTransferSnapshot?> snapshot() async {
    final map = await _commands.invokeMapMethod<Object?, Object?>('snapshot');
    return map == null ? null : BackupTransferSnapshot.fromMap(map);
  }

  Future<BackupTransferSnapshot> _call(
    String method, [
    Map<String, Object?>? args,
  ]) async => BackupTransferSnapshot.fromMap(
    (await _commands.invokeMapMethod<Object?, Object?>(method, args))!,
  );

  Future<BackupTransferSnapshot> release(String taskId) =>
      _call('release', {'taskId': taskId});

  /// Confirmation must be made from the foreground before restarting work.
  Future<void> placeImport(
    BackupLease lease,
    List<Map<String, Object?>> files,
    LibraryCoordinator coordinator,
  ) async {
    lease.checkCancelled();
    await _call('placeImport', {'taskId': lease.taskId, 'files': files});
    while (true) {
      if (lease.cancelRequested) {
        await _commands.invokeMethod<void>('cancel', {'taskId': lease.taskId});
      }
      final value = await snapshot();
      if (value == null || value.taskId != lease.taskId) {
        throw StateError('Native import task was replaced');
      }
      coordinator.report(
        lease,
        BackupProgress(
          taskId: lease.taskId,
          sequence: (lease.progress?.sequence ?? 0) + 1,
          operation: lease.operation,
          stage: BackupStage.importing,
          processedBytes: value.processedBytes,
          totalBytes: value.totalBytes,
          processedRecordings: value.processedRecordings,
        ),
      );
      if (!value.isRunning) {
        lease.checkCancelled();
        if (value.status != 'completed') throw BackupTransferException(value);
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// New engine/process startup barrier. A surviving native transfer drains
  /// before any recording recovery or library writes. Never resumes a workflow.
  Future<void> recoverInterruptedTransfer() async {
    var value = await snapshot();
    while (value?.isRunning ?? false) {
      await Future<void>.delayed(pollInterval);
      value = await snapshot();
    }
    if (value == null) return;
    final cleaned = await release(value.taskId);
    if (cleaned.cleanupPending) throw BackupTransferException(cleaned);
    // A residual provider target is reported in the retained snapshot. It is
    // never treated as a usable backup, and native admission rejects a new job.
  }

  /// Owns the lease and transport lifecycle. [createExportRequest] switches to
  /// the native complete-export worker; otherwise this only copies a document.
  /// Select the document first, so picker cancellation never acquires the gate.
  Future<T> copy<T>({
    required RecordingService recordingService,
    required BackupDocument document,
    required bool write,
    bool importArchive = false,
    Future<T> Function(BackupTransferSnapshot value, BackupLease lease)?
    consumeImport,
    Future<void> Function()? afterTransfer,
    void Function(Object error)? onImportCleanupError,
    Future<void> Function(String stagedPath)? prepareOutput,
    Future<Map<String, Object?>> Function(BackupLease lease)?
    createExportRequest,
    required Future<T> Function(BackupTransferSnapshot value) consume,
  }) async {
    final prepared = await _call('prepare', {
      'uri': document.uri,
      'displayName': document.displayName,
      'direction': write ? 'write' : 'read',
    });
    var admitted = false;
    try {
      return await recordingService.runBackup(
        taskId: prepared.taskId,
        operation: write ? BackupOperation.export : BackupOperation.import,
        action: (lease) async {
          admitted = true;
          T? committedImport;
          var importCommitted = false;
          try {
            final export = await createExportRequest?.call(lease);
            await prepareOutput?.call(prepared.stagedPath);
            lease.checkCancelled();
            await _call(
              importArchive
                  ? 'startImport'
                  : export == null
                  ? 'startCopy'
                  : 'startExport',
              {
                'taskId': prepared.taskId,
                'direction': write ? 'write' : 'read',
                'uri': document.uri,
                'export': ?export,
              },
            );
            var lastSequence = -1;
            var cancelled = false;
            while (true) {
              if (lease.cancelRequested && !cancelled) {
                await _commands.invokeMethod<void>('cancel', {
                  'taskId': prepared.taskId,
                });
                cancelled = true;
              }
              final value = await snapshot();
              if (value == null || value.taskId != lease.taskId) {
                throw StateError('Native backup task was replaced');
              }
              if (value.sequence > lastSequence) {
                lastSequence = value.sequence;
                final coordinator = recordingService.coordinator;
                coordinator.report(
                  lease,
                  BackupProgress(
                    taskId: lease.taskId,
                    sequence: (lease.progress?.sequence ?? 0) + 1,
                    operation: lease.operation,
                    stage: cancelled || value.cancelRequested
                        ? BackupStage.cancelling
                        : value.stage == 'preparing'
                        ? BackupStage.preparing
                        : value.stage == 'packing'
                        ? BackupStage.packing
                        : value.stage == 'verifying'
                        ? BackupStage.verifying
                        : write
                        ? BackupStage.saving
                        : BackupStage.checking,
                    processedBytes: value.processedBytes,
                    totalBytes: value.totalBytes,
                    processedRecordings: value.processedRecordings,
                  ),
                );
              }
              if (!value.isRunning) {
                if (value.status == 'cancelled') {
                  throw const BackupCancelledException();
                }
                if (value.status != 'completed') {
                  throw BackupTransferException(value);
                }
                if (!value.exportCommitted) lease.checkCancelled();
                final result = consumeImport == null
                    ? await consume(value)
                    : await consumeImport(value, lease);
                if (importArchive) {
                  committedImport = result;
                  importCommitted = true;
                }
                if (!value.exportCommitted) {
                  // A successful import callback has committed SQLite. Late
                  // cancellation must never turn that success into a rollback.
                  if (!importArchive) lease.checkCancelled();
                  await _commands.invokeMethod<void>('accept', {
                    'taskId': lease.taskId,
                  });
                }
                return result;
              }
              await Future<void>.delayed(pollInterval);
            }
          } catch (error) {
            if (!importCommitted) rethrow;
            onImportCleanupError?.call(error);
            return committedImport as T;
          } finally {
            try {
              await _settle(prepared.taskId);
              await afterTransfer?.call();
            } catch (error) {
              if (!importCommitted) rethrow;
              onImportCleanupError?.call(error);
            }
          }
        },
      );
    } finally {
      if (!admitted) await _settle(prepared.taskId);
    }
  }

  Future<void> _settle(String id) async {
    var value = await snapshot();
    if (value?.taskId != id) {
      throw StateError('Native backup task was replaced');
    }
    if (value!.isRunning) {
      await _commands.invokeMethod<void>('cancel', {'taskId': id});
      do {
        await Future<void>.delayed(pollInterval);
        value = await snapshot();
        if (value?.taskId != id) {
          throw StateError('Native backup task was replaced');
        }
      } while (value!.isRunning);
    }
    final cleaned = await release(id);
    if (cleaned.cleanupPending && !cleaned.exportCommitted ||
        cleaned.residualUri != null) {
      throw BackupTransferException(cleaned);
    }
  }
}
