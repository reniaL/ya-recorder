import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../recording/recording_service.dart';
import '../storage/app_storage_paths.dart';
import '../storage/models/recording.dart';
import '../storage/models/recording_folder.dart';
import '../storage/recording_store.dart';
import 'backup_contract.dart' as contract;
import 'backup_document_service.dart';
import 'backup_progress.dart';
import 'library_coordinator.dart';

class BackupImportPlan {
  BackupImportPlan({
    required this.backup,
    required List<RecordingFolder> folders,
    required List<contract.BackupRecording> recordings,
    required this.duplicates,
    required this.conflicts,
    required Map<String, String> renamedFolders,
  }) : folders = List.unmodifiable(folders),
       recordings = List.unmodifiable(recordings),
       renamedFolders = Map.unmodifiable(renamedFolders);
  final contract.BackupDocument backup;
  final List<RecordingFolder> folders;
  final List<contract.BackupRecording> recordings;
  final int duplicates;
  final int conflicts;
  final Map<String, String> renamedFolders;
  int get audioBytes => recordings.fold(0, (sum, r) => sum + r.file.size);
}

class BackupImportResult {
  BackupImportResult(this.plan, {this.cleanupPending = false});
  final BackupImportPlan plan;
  bool cleanupPending;
  bool get hasAdditions =>
      plan.recordings.isNotEmpty || plan.folders.isNotEmpty;
}

/// Filesystem journal only establishes ownership. SQLite is the commit authority.
class BackupImportRecovery {
  BackupImportRecovery(this.paths, this.store, {this.onRecovered});
  final AppStoragePaths paths;
  final RecordingStore store;
  final void Function(String taskId, bool committed)? onRecovered;
  Directory get journals =>
      Directory(path.join(paths.rootDirectory.path, 'backup-imports'));
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  Directory destination(String id) {
    if (!_uuid.hasMatch(id)) throw StateError('Invalid import task ID');
    return Directory(path.join(paths.recordingsDirectory.path, 'import-$id'));
  }

  File journal(String id) {
    destination(id); // Validate before deriving any path.
    return File(path.join(journals.path, '$id.json'));
  }

  Future<void> prepare(String id, List<String> names) async {
    final directory = destination(id);
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Import directory occupied');
    }
    await journals.create(recursive: true);
    final file = journal(id);
    if (await file.exists()) throw StateError('Import journal occupied');
    final pending = File('${file.path}.pending');
    await pending.writeAsString(
      jsonEncode({'version': 1, 'taskId': id, 'files': names}),
      flush: true,
    );
    await pending.rename(
      file.path,
    ); // Durable before ANY final audio is created.
    await directory.create();
  }

  Future<void> recover() async {
    if (!await journals.exists()) return;
    await for (final entity in journals.list(followLinks: false)) {
      if (entity is! File) throw StateError('Unexpected import journal entry');
      if (entity.path.endsWith('.pending')) {
        final id = path.basename(entity.path).replaceFirst('.json.pending', '');
        destination(id);
        // No final file can be created before the journal rename.
        await entity.delete();
      } else {
        final id = path.basenameWithoutExtension(entity.path);
        await settle(id);
      }
    }
  }

  Future<void> settle(String id) async {
    final file = journal(id);
    if (!await file.exists()) return;
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('Import journal is not a regular file');
    }
    if (await file.length() > 2 * 1024 * 1024) {
      throw StateError('Import journal too large');
    }
    final value = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (value['version'] != 1 || value['taskId'] != id) {
      throw StateError('Invalid import journal');
    }
    final names = (value['files'] as List).cast<String>();
    if (names.length > 10000 ||
        names.toSet().length != names.length ||
        names.any(
          (n) => !RegExp(
            r'^recording-[A-Za-z0-9_-]{1,128}\.(aac|mp3|m4a)$',
          ).hasMatch(n),
        )) {
      throw StateError('Invalid import ownership inventory');
    }
    final committed = await store.importWasCommitted(id);
    if (!committed) {
      final directory = destination(id);
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound) {
        if (type != FileSystemEntityType.directory) {
          throw StateError('Ambiguous import ownership');
        }
        // Validate ALL ownership before deleting anything. Never follow links or
        // delete unexpected files, even if they live under this task directory.
        final entries = await directory.list(followLinks: false).toList();
        if (entries.any(
          (e) => e is! File || !names.contains(path.basename(e.path)),
        )) {
          throw StateError('Ambiguous import files; retained for inspection');
        }
        for (final entity in entries) {
          await entity.delete();
        }
        await directory.delete();
      }
    } else if (names.isEmpty) {
      final directory = destination(id);
      if (await directory.exists() && await directory.list().isEmpty) {
        await directory.delete();
      }
    }
    // Journal removal must precede commit-marker removal. A surviving journal
    // must never observe a missing marker for already committed audio.
    await file.delete();
    await store.forgetImportCommit(id);
    onRecovered?.call(id, committed);
  }
}

class BackupImportService {
  BackupImportService({BackupDocumentService? documents})
    : documents = documents ?? BackupDocumentService();
  final BackupDocumentService documents;

  Future<BackupImportResult> import({
    required RecordingStore store,
    required RecordingService recordingService,
    required AppStoragePaths paths,
    required BackupDocument source,
    required Future<bool> Function(BackupImportPlan) confirm,
  }) async {
    recordingService.bindLibraryCoordinator(store.coordinator);
    final recovery = BackupImportRecovery(paths, store);
    BackupImportResult? committed;
    try {
      return await documents.copy<BackupImportResult>(
        recordingService: recordingService,
        document: source,
        write: false,
        importArchive: true,
        consume: (_) => throw StateError('Import lease required'),
        onImportCleanupError: (_) => committed!.cleanupPending = true,
        afterTransfer: () async {
          try {
            await recovery.recover();
          } catch (_) {
            if (committed == null) rethrow;
            committed!.cleanupPending = true;
          }
        },
        consumeImport: (value, lease) async {
          final reportFile = File(
            path.join(path.dirname(value.stagedPath), 'verified.json'),
          );
          final backup = await _readInWorker(reportFile.path);
          lease.checkCancelled();
          final local = await store.allRecordingsForBackup(lease);
          final snapshot = await store.snapshotForBackup(lease);
          final plan = await createPlan(backup, local, snapshot.folders, lease);
          await documents.recordImportSummary(
            lease,
            recordings: plan.recordings.length,
            folders: plan.folders.length,
            duplicates: plan.duplicates,
            conflicts: plan.conflicts,
          );
          void report(BackupStage stage) => store.coordinator.report(
            lease,
            BackupProgress(
              taskId: lease.taskId,
              sequence: (lease.progress?.sequence ?? 0) + 1,
              operation: lease.operation,
              stage: stage,
              processedBytes: 0,
              processedRecordings: 0,
            ),
          );
          report(BackupStage.awaitingConfirmation);
          final accepted = await Future.any<bool>([
            Future<bool>.sync(() => confirm(plan)),
            lease.whenCancelled.then((_) => false),
          ]);
          if (!accepted) throw const BackupCancelledException();
          lease.checkCancelled();
          final directory = recovery.destination(lease.taskId);
          final recordings = [
            for (final r in plan.recordings)
              Recording(
                id: r.id,
                title: r.title,
                createdAt: r.createdAt,
                duration: Duration(milliseconds: r.durationMs),
                fileSizeBytes: r.file.size,
                format: r.format,
                folderId: r.folderId,
                wasInterrupted: r.wasInterrupted,
                filePath: path.join(directory.path, path.basename(r.file.path)),
              ),
          ];
          for (final r in plan.recordings) {
            final canonical = paths.completedRecordingFile(
              r.id,
              format: r.format,
            );
            if (await FileSystemEntity.type(
                  canonical.path,
                  followLinks: false,
                ) !=
                FileSystemEntityType.notFound) {
              throw StateError('Unindexed target audio exists: ${r.id}');
            }
          }
          await recovery.prepare(
            lease.taskId,
            recordings.map((r) => path.basename(r.filePath)).toList(),
          );
          report(BackupStage.importing);
          if (recordings.isNotEmpty) {
            await documents.placeImport(lease, [
              for (final r in recordings)
                {'name': path.basename(r.filePath), 'target': r.filePath},
            ], store.coordinator);
          }
          lease.checkCancelled();
          report(BackupStage.committing);
          await store.backupTransaction(lease, (txn) async {
            for (final f in plan.folders) {
              await txn.insert('folders', f.toDatabaseMap());
            }
            for (final r in recordings) {
              await txn.insert('recordings', r.toDatabaseMap());
            }
            await txn.insert('backup_import_commits', {
              'task_id': lease.taskId,
              'committed_at': DateTime.now().toUtc().millisecondsSinceEpoch,
            });
          });
          committed = BackupImportResult(plan);
          return committed!;
        },
      );
    } catch (_) {
      if (committed == null) rethrow;
      return BackupImportResult(committed!.plan, cleanupPending: true);
    }
  }

  static Future<BackupImportPlan> createPlan(
    contract.BackupDocument backup,
    List<Recording> local,
    List<RecordingFolder> folders,
    BackupLease lease,
  ) async {
    final byId = {for (final r in local) r.id: r};
    final additions = <contract.BackupRecording>[];
    var duplicates = 0;
    var conflicts = 0;
    for (final r in backup.recordings) {
      lease.checkCancelled();
      final existing = byId[r.id];
      if (existing == null) {
        additions.add(r);
        continue;
      }
      final file = File(existing.filePath);
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() != existing.fileSizeBytes ||
          existing.fileSizeBytes <= 0) {
        throw StateError('Local audio unavailable for existing ID: ${r.id}');
      }
      final hash = await _hashInWorker(file.path);
      if (hash == r.file.sha256Hex &&
          existing.title == r.title &&
          existing.createdAt == r.createdAt &&
          existing.duration.inMilliseconds == r.durationMs &&
          existing.format == r.format &&
          existing.folderId == r.folderId &&
          existing.wasInterrupted == r.wasInterrupted) {
        duplicates++;
      } else {
        conflicts++;
      }
    }
    String fold(String s) =>
        s.replaceAllMapped(RegExp('[A-Z]'), (m) => m[0]!.toLowerCase());
    final ids = folders.map((f) => f.id).toSet();
    final names = folders.map((f) => fold(f.name)).toSet();
    var order =
        folders.fold<int>(-1, (n, f) => n > f.sortOrder ? n : f.sortOrder) + 1;
    final addedFolders = <RecordingFolder>[];
    final renamed = <String, String>{};
    final ordered = [...backup.folders]
      ..sort((a, b) {
        final compare = a.sortOrder.compareTo(b.sortOrder);
        return compare == 0 ? a.id.compareTo(b.id) : compare;
      });
    for (final f in ordered) {
      if (ids.contains(f.id)) continue;
      var name = f.name;
      var suffix = 1;
      while (names.contains(fold(name))) {
        name = suffix == 1 ? '${f.name}（导入）' : '${f.name}（导入 $suffix）';
        suffix++;
      }
      if (name != f.name) renamed[f.id] = name;
      names.add(fold(name));
      addedFolders.add(
        RecordingFolder(
          id: f.id,
          name: name,
          createdAt: f.createdAt,
          sortOrder: order++,
        ),
      );
    }
    return BackupImportPlan(
      backup: backup,
      folders: addedFolders,
      recordings: additions,
      duplicates: duplicates,
      conflicts: conflicts,
      renamedFolders: renamed,
    );
  }

  /// The native adapter hashes every entry, including duplicate recording IDs.
  // Keep isolate closures in a separate scope so they cannot capture a lease,
  // MethodChannel, database or confirmation callback from the import stack.
  static Future<contract.BackupDocument> _readInWorker(String reportPath) =>
      Isolate.run(() => readVerifiedBackup(reportPath));

  static Future<String> _hashInWorker(String filePath) => Isolate.run(
    () async =>
        (await sha256.bind(File(filePath).openRead()).single).toString(),
  );

  static Future<contract.BackupDocument> readVerifiedBackup(
    String reportPath,
  ) async {
    final report = File(reportPath);
    if (await report.length() > 80 * 1024 * 1024) {
      throw StateError('Oversized verification report');
    }
    final value =
        jsonDecode(await report.readAsString()) as Map<String, dynamic>;
    final entries = (value['entries'] as List).cast<Map<String, dynamic>>();
    final backup = const contract.BackupContract().parse(
      manifestBytes: utf8.encode(value['manifest'] as String),
      metadataBytes: utf8.encode(value['metadata'] as String),
      entries: [
        for (final e in entries)
          contract.BackupEntry(
            path: e['path'] as String,
            size: e['size'] as int,
          ),
      ],
    );
    final hashes = {for (final e in entries) e['path']: e['sha256']};
    for (final f in backup.files) {
      if (hashes[f.path] != f.sha256Hex) {
        throw contract.BackupValidationException(
          contract.BackupErrorCode.checksumMismatch,
          f.path,
        );
      }
    }
    return backup;
  }
}
