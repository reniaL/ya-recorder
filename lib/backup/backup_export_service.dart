import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../recording/recording_service.dart';
import '../storage/recording_store.dart';
import 'backup_contract.dart' as contract;
import 'backup_document_service.dart';

/// Conservative STORE/ZIP64 overhead. A provider's free space is unknown;
/// source files already exist and are not duplicated before packaging.
class BackupExportEstimate {
  const BackupExportEstimate({
    required this.audioBytes,
    required this.temporaryBytes,
  });
  final int audioBytes;
  final int temporaryBytes;
  int get localTargetCopyBytes => temporaryBytes;
  int get combinedLocalBytes => temporaryBytes + localTargetCopyBytes;
  int? get targetAvailableBytes => null;
  // Hash, package and verify the archive, then read it to save to the provider.
  int get approximateReadBytes => audioBytes * 4;
}

class BackupExportPlan {
  BackupExportPlan._(
    this.request,
    this.recordingCount,
    this.folderCount,
    this.estimate,
  );
  final Map<String, Object?> request;
  final int recordingCount;
  final int folderCount;
  final BackupExportEstimate estimate;

  factory BackupExportPlan.fromSnapshot(
    LibrarySnapshot snapshot,
    DateTime createdAt,
  ) {
    final recordings = snapshot.recordings.where((r) => !r.isDeleted).toList();
    final folders = snapshot.folders
        .map(
          (f) => contract.BackupFolder(f.id, f.name, f.createdAt, f.sortOrder),
        )
        .toList();
    final files = recordings
        .map(
          (r) => contract.BackupFile(
            'recordings/recording-${r.id}.${r.format.extension}',
            r.fileSizeBytes,
            '0' * 64,
          ),
        )
        .toList();
    final models = [
      for (var i = 0; i < recordings.length; i++)
        contract.BackupRecording(
          id: recordings[i].id,
          title: recordings[i].title,
          createdAt: recordings[i].createdAt,
          durationMs: recordings[i].duration.inMilliseconds,
          format: recordings[i].format,
          file: files[i],
          folderId: recordings[i].folderId,
          wasInterrupted: recordings[i].wasInterrupted,
        ),
    ];
    final draft = contract.BackupDocument(
      createdAt: createdAt,
      files: files,
      folders: folders,
      recordings: models,
    );
    final metadata = utf8.encode(jsonEncode(draft.metadataJson()));
    final inventory = [
      contract.BackupFile(
        'metadata.json',
        metadata.length,
        sha256.convert(metadata).toString(),
      ),
      ...files,
    ];
    final envelope = contract.BackupDocument(
      createdAt: createdAt,
      files: inventory,
      folders: folders,
      recordings: models,
    );
    final manifest = utf8.encode(jsonEncode(envelope.manifestJson()));
    // Reuse the v1 contract before crossing the bridge. Zero hashes above are
    // validation placeholders only; the native worker computes all real hashes.
    const contract.BackupContract().parse(
      manifestBytes: manifest,
      metadataBytes: metadata,
      entries: [
        contract.BackupEntry(path: 'manifest.json', size: manifest.length),
        for (final file in inventory)
          contract.BackupEntry(path: file.path, size: file.size),
      ],
    );
    final audio = files.fold<int>(0, (sum, file) => sum + file.size);
    final manifestBudget = (recordings.length + 1) * 512 + 512;
    final upperBound =
        audio +
        metadata.length +
        manifestBudget +
        (recordings.length + 2) * 512 +
        65536;
    return BackupExportPlan._(
      {
        'metadataJson': utf8.decode(metadata),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'folderCount': folders.length,
        'sources': [
          for (var i = 0; i < recordings.length; i++)
            {
              'path': files[i].path,
              'filePath': recordings[i].filePath,
              'size': files[i].size,
            },
        ],
      },
      recordings.length,
      folders.length,
      BackupExportEstimate(audioBytes: audio, temporaryBytes: upperBound),
    );
  }
}

class BackupExportResult {
  const BackupExportResult({
    required this.document,
    required this.recordingCount,
    required this.folderCount,
    required this.archiveBytes,
    required this.cachedArchivePath,
    required this.retainedUntil,
  });
  final BackupDocument document;
  final int recordingCount;
  final int folderCount;
  final int archiveBytes;

  /// Share targets may read later: native cleanup retains this for 24 hours.
  final String? cachedArchivePath;
  final DateTime? retainedUntil;
}

class BackupExportService {
  BackupExportService({BackupDocumentService? documents})
    : documents = documents ?? BackupDocumentService();
  final BackupDocumentService documents;

  Future<BackupExportResult> export({
    required RecordingStore store,
    required RecordingService recordingService,
    required BackupDocument destination,
    DateTime? createdAt,
  }) async {
    recordingService.bindLibraryCoordinator(store.coordinator);
    BackupExportPlan? plan;
    return documents.copy(
      recordingService: recordingService,
      document: destination,
      write: true,
      createExportRequest: (lease) async {
        final snapshot = await store.snapshotForBackup(lease);
        lease.checkCancelled();
        plan = BackupExportPlan.fromSnapshot(
          snapshot,
          createdAt ?? DateTime.now().toUtc(),
        );
        return plan!.request;
      },
      consume: (value) async {
        if (!value.exportCommitted) {
          throw StateError('Native export was not committed');
        }
        return BackupExportResult(
          document: destination,
          recordingCount: plan!.recordingCount,
          folderCount: plan!.folderCount,
          archiveBytes: value.processedBytes,
          cachedArchivePath: value.cachedArchivePath,
          retainedUntil: value.retainedUntilMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  value.retainedUntilMs!,
                  isUtc: true,
                ),
        );
      },
    );
  }
}
