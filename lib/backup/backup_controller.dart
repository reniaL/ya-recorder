import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

import '../recording/recording_service.dart';
import '../storage/app_storage_paths.dart';
import '../storage/recording_store.dart';
import 'backup_contract.dart';
import 'backup_document_service.dart' as transport;
import 'backup_export_service.dart';
import 'backup_import_service.dart';
import 'backup_progress.dart';
import 'library_coordinator.dart';

enum BackupFailure {
  busy,
  invalid,
  version,
  zip64,
  space,
  permission,
  local,
  interrupted,
  cleanup,
  unknown,
}

BackupFailure classifyBackupFailure(Object error) {
  if (error is LibraryBusyException) return BackupFailure.busy;
  if (error is BackupValidationException) {
    return error.code == BackupErrorCode.unsupportedVersion
        ? BackupFailure.version
        : BackupFailure.invalid;
  }
  final detail = error is transport.BackupTransferException
      ? '${error.snapshot.error} ${error.snapshot.errorDetail}'
      : error.toString();
  if (detail.contains('zip64')) return BackupFailure.zip64;
  if (detail.contains('space') ||
      detail.contains('ENOSPC') ||
      detail.contains('No space')) {
    return BackupFailure.space;
  }
  if (detail.contains('permission') || detail.contains('SecurityException')) {
    return BackupFailure.permission;
  }
  if (detail.contains('Local audio') ||
      detail.contains('source-missing-or-inconsistent') ||
      detail.contains('source-changed') ||
      detail.contains('Unindexed target') ||
      detail.contains('directory occupied')) {
    return BackupFailure.local;
  }
  if (detail.contains('interrupted') ||
      detail.contains('timeout') ||
      detail.contains('service-destroyed')) {
    return BackupFailure.interrupted;
  }
  if (detail.contains('cleanup') || detail.contains('ownership')) {
    return BackupFailure.cleanup;
  }
  if (detail.contains('archive') ||
      detail.contains('entry') ||
      detail.contains('zip-') ||
      detail.contains('ZIP')) {
    return BackupFailure.invalid;
  }
  return BackupFailure.unknown;
}

enum BackupOutcome {
  exported,
  imported,
  cancelled,
  failed,
  recoveredImport,
  interrupted,
}

class RestoredImportSummary {
  const RestoredImportSummary(
    this.recordings,
    this.folders,
    this.duplicates,
    this.conflicts,
  );
  final int recordings;
  final int folders;
  final int duplicates;
  final int conflicts;
}

/// Application-owned workflow. Routes only observe and answer the confirmation;
/// no BuildContext, locale or widget lifetime is captured by a running task.
class BackupController extends ChangeNotifier {
  BackupController({
    required this.store,
    required this.recordingService,
    transport.BackupDocumentService? documents,
    BackupExportService? exporter,
    BackupImportService? importer,
    Future<ShareResult> Function(ShareParams)? share,
  }) : documents = documents ?? transport.BackupDocumentService(),
       _exporter = exporter,
       _importer = importer,
       _share = share ?? SharePlus.instance.share {
    recordingService.bindLibraryCoordinator(store.coordinator);
    store.coordinator.addListener(_changed);
  }
  final RecordingStore store;
  final RecordingService recordingService;
  final transport.BackupDocumentService documents;
  final BackupExportService? _exporter;
  final BackupImportService? _importer;
  final Future<ShareResult> Function(ShareParams) _share;
  AppStoragePaths get paths =>
      AppStoragePaths(Directory(path.dirname(store.databasePath)));
  LibraryCoordinator get coordinator => store.coordinator;
  BackupProgress? get progress => coordinator.progress;
  bool _busy = false;
  bool _disposed = false;
  int _workflowVersion = 0;
  int _initializationVersion = 0;
  bool get busy => _busy || coordinator.isProtected;
  bool picking = false;
  bool sharing = false;
  bool shareHandedOff = false;
  bool shareFailed = false;
  BackupExportPlan? exportReview;
  BackupImportPlan? importPreview;
  BackupExportResult? exported;
  BackupImportResult? imported;
  RestoredImportSummary? restoredImportSummary;
  bool startupFailure = false;
  BackupOutcome? outcome;
  BackupFailure? failure;
  String? residualUri;
  String? taskId;
  String? documentName;
  Completer<bool>? _confirmation;
  VoidCallback? onOpenRequested;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    startupFailure = false;
    _changed();
    final workflowVersion = _workflowVersion;
    final initializationVersion = ++_initializationVersion;
    documents.setOpenTaskHandler((id) async {
      final current = coordinator.activeTask?.taskId ?? taskId;
      if (id == current) onOpenRequested?.call();
    });
    try {
      final snapshot = await documents.snapshot();
      if (!busy &&
          snapshot != null &&
          workflowVersion == _workflowVersion &&
          initializationVersion == _initializationVersion) {
        exported = null;
        imported = null;
        restoredImportSummary = null;
        outcome = null;
        failure = null;
        taskId = snapshot.taskId;
        if (snapshot.exportCommitted) {
          exported = BackupExportResult(
            document: transport.BackupDocument(
              uri: snapshot.uri ?? '',
              displayName: snapshot.displayName ?? 'backup.zip',
            ),
            recordingCount: snapshot.recordingCount,
            folderCount: snapshot.folderCount,
            archiveBytes: snapshot.processedBytes,
            cachedArchivePath: snapshot.cachedArchivePath,
            retainedUntil: snapshot.retainedUntilMs == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    snapshot.retainedUntilMs!,
                    isUtc: true,
                  ),
          );
          outcome = BackupOutcome.exported;
        } else if (snapshot.kind == 'import' && snapshot.accepted ||
            coordinator.recoveredImportTaskId == snapshot.taskId &&
                coordinator.recoveredImportCommitted == true) {
          outcome = BackupOutcome.recoveredImport;
          if (snapshot.importSummaryKnown) {
            restoredImportSummary = RestoredImportSummary(
              snapshot.recordingCount,
              snapshot.folderCount,
              snapshot.duplicateCount,
              snapshot.conflictCount,
            );
          }
        } else if (snapshot.status == 'cancelled') {
          outcome = BackupOutcome.cancelled;
        } else if (snapshot.status == 'failed') {
          outcome = BackupOutcome.failed;
          failure = classifyBackupFailure(
            transport.BackupTransferException(snapshot),
          );
        } else if (snapshot.kind != null || snapshot.status == 'interrupted') {
          outcome = BackupOutcome.interrupted;
        }
        residualUri = snapshot.residualUri;
        if (residualUri != null && !snapshot.exportCommitted) {
          outcome = BackupOutcome.failed;
          failure = BackupFailure.cleanup;
        }
        _changed();
      }
      final open = await documents.takeOpenTask();
      if (open != null && open == (coordinator.activeTask?.taskId ?? taskId)) {
        onOpenRequested?.call();
      }
    } on MissingPluginException {
      /* Standalone non-Android test hosts. */
    } on PlatformException {
      /* Startup gate reports cleanup errors separately. */
    }
  }

  void showStartupFailure(Object error) {
    _reset();
    startupFailure = true;
    outcome = BackupOutcome.failed;
    failure = classifyBackupFailure(error);
    if (failure == BackupFailure.unknown) failure = BackupFailure.cleanup;
    _changed();
  }

  Future<void> retryRecovery() async {
    if (busy) return;
    _busy = true;
    _changed();
    try {
      await documents.recoverInterruptedTransfer();
      await coordinator.ensureInitialized();
      startupFailure = false;
    } catch (error) {
      showStartupFailure(error);
    } finally {
      _busy = false;
    }
    if (!startupFailure) await initialize();
    _changed();
  }

  void _reset() {
    _workflowVersion++;
    outcome = null;
    failure = null;
    exported = null;
    imported = null;
    restoredImportSummary = null;
    importPreview = null;
    exportReview = null;
    residualUri = null;
    shareHandedOff = false;
    shareFailed = false;
  }

  Future<void> reviewExport() async {
    if (busy || sharing || startupFailure) return;
    _busy = true;
    _reset();
    _changed();
    try {
      final recordings = await store.listRecordings();
      final folders = await store.listFolders();
      exportReview = BackupExportPlan.fromSnapshot(
        LibrarySnapshot(
          folders,
          recordings,
          recordings.map((r) => r.id).toSet(),
        ),
        DateTime.now().toUtc(),
      );
    } catch (error) {
      _fail(error);
    } finally {
      _busy = false;
      _changed();
    }
  }

  void dismissReview() {
    if (!busy) {
      exportReview = null;
      _changed();
    }
  }

  static String suggestedName(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '丫丫录音备份-${time.year}${two(time.month)}${two(time.day)}-${two(time.hour)}${two(time.minute)}${two(time.second)}.zip';
  }

  Future<void> startExport() async {
    if (busy || sharing || startupFailure || exportReview == null) return;
    _busy = true;
    picking = true;
    _changed();
    try {
      final target = await documents.pickTarget(suggestedName(DateTime.now()));
      picking = false;
      if (target == null) return;
      _reset();
      documentName = target.displayName;
      _changed();
      exported = await (_exporter ?? BackupExportService(documents: documents))
          .export(
            store: store,
            recordingService: recordingService,
            destination: target,
          );
      outcome = BackupOutcome.exported;
    } catch (error) {
      _fail(error);
    } finally {
      taskId = progress?.taskId;
      picking = false;
      _busy = false;
      _changed();
    }
  }

  Future<void> startImport() async {
    if (busy || sharing || startupFailure) return;
    _busy = true;
    picking = true;
    _changed();
    try {
      final source = await documents.pickSource();
      picking = false;
      if (source == null) return;
      _reset();
      documentName = source.displayName;
      _changed();
      imported = await (_importer ?? BackupImportService(documents: documents))
          .import(
            store: store,
            recordingService: recordingService,
            paths: paths,
            source: source,
            confirm: (plan) {
              importPreview = plan;
              _confirmation = Completer<bool>();
              _changed();
              return _confirmation!.future;
            },
          );
      outcome = BackupOutcome.imported;
    } catch (error) {
      _fail(error);
    } finally {
      taskId = progress?.taskId;
      importPreview = null;
      _confirmation = null;
      picking = false;
      _busy = false;
      _changed();
    }
  }

  void confirmImport() {
    final value = _confirmation;
    if (value == null || value.isCompleted) return;
    importPreview = null;
    value.complete(true);
    _changed();
  }

  void cancel() {
    final lease = coordinator.activeTask;
    if (lease == null || !(lease.progress?.canCancel ?? false)) return;
    coordinator.requestCancel(lease);
    final value = _confirmation;
    if (value != null && !value.isCompleted) value.complete(false);
    _changed();
  }

  void _fail(Object error) {
    _reset();
    outcome = error is BackupCancelledException
        ? BackupOutcome.cancelled
        : BackupOutcome.failed;
    failure = classifyBackupFailure(error);
    if (error is transport.BackupTransferException) {
      residualUri = error.snapshot.residualUri;
    }
  }

  Future<void> shareExport() async {
    final result = exported;
    if (busy || sharing || result?.cachedArchivePath == null) return;
    sharing = true;
    shareFailed = false;
    shareHandedOff = false;
    _changed();
    try {
      final file = File(result!.cachedArchivePath!);
      if (result.retainedUntil == null ||
          !result.retainedUntil!.isAfter(DateTime.now()) ||
          !await file.exists()) {
        throw StateError('Share copy expired');
      }
      final value = await _share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/zip')],
          fileNameOverrides: [result.document.displayName],
        ),
      );
      shareHandedOff = value.status == ShareResultStatus.success;
    } catch (_) {
      shareFailed = true;
    } finally {
      sharing = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final confirmation = _confirmation;
    if (confirmation != null && !confirmation.isCompleted) {
      confirmation.complete(false);
    }
    coordinator.removeListener(_changed);
    documents.setOpenTaskHandler(null);
    onOpenRequested = null;
    super.dispose();
  }
}
