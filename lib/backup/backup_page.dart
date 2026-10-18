import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/localization.dart';
import 'backup_controller.dart';
import 'backup_import_service.dart';
import 'backup_progress.dart';

String backupBytes(int bytes, String locale) {
  final units = ['B', 'KiB', 'MiB', 'GiB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${NumberFormat('#,##0.#', locale).format(value)} ${units[index]}';
}

String backupStageLabel(AppLocalizations s, BackupStage? stage) =>
    switch (stage) {
      BackupStage.preparing => s.backupPreparing,
      BackupStage.checking => s.backupChecking,
      BackupStage.awaitingConfirmation => s.backupPreview,
      BackupStage.packing => s.backupPacking,
      BackupStage.verifying => s.backupVerifying,
      BackupStage.saving => s.backupSaving,
      BackupStage.importing => s.backupImporting,
      BackupStage.committing => s.backupCommitting,
      BackupStage.cancelling => s.backupCancelling,
      _ => s.backupWorking,
    };

String backupFailureLabel(AppLocalizations s, BackupFailure? failure) =>
    switch (failure) {
      BackupFailure.busy => s.backupErrorBusy,
      BackupFailure.invalid => s.backupErrorInvalid,
      BackupFailure.version => s.backupErrorVersion,
      BackupFailure.zip64 => s.backupZip64,
      BackupFailure.space => s.backupErrorSpace,
      BackupFailure.startup => s.backupErrorStartup,
      BackupFailure.permission => s.backupErrorPermission,
      BackupFailure.local => s.backupErrorLocal,
      BackupFailure.interrupted => s.backupInterrupted,
      BackupFailure.cleanup => s.backupErrorCleanup,
      _ => s.backupErrorUnknown,
    };

class BackupProtectionNotice extends StatelessWidget {
  const BackupProtectionNotice({super.key, this.onOpen});
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n(context).backupProtected),
        if (onOpen != null)
          TextButton(
            onPressed: onOpen,
            child: Text(l10n(context).backupCurrentTask),
          ),
      ],
    ),
  );
}

class BackupPage extends StatelessWidget {
  const BackupPage({super.key, required this.controller});
  final BackupController controller;

  Widget _text(String value, {bool heading = false, Key? key}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      value,
      key: key,
      style: heading
          ? const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)
          : null,
    ),
  );
  Widget _button(String text, VoidCallback? action, String key) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: FilledButton(
      key: Key(key),
      onPressed: action,
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.all(12),
      ),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );

  List<Widget> _plan(
    BuildContext context,
    BackupImportPlan plan, {
    bool result = false,
  }) {
    final s = l10n(context);
    final renamed = plan.renamedFolders.entries.toList();
    final folderNames = {for (final f in plan.backup.folders) f.id: f.name};
    return [
      _text(
        result
            ? s.backupAddedResult(plan.recordings.length)
            : s.backupAddedCount(plan.recordings.length),
      ),
      _text(s.backupFoldersCount(plan.folders.length)),
      _text(s.backupDuplicateCount(plan.duplicates)),
      _text(s.backupConflictCount(plan.conflicts)),
      if (plan.renamedFolders.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (context) => SafeArea(
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * .7,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(l10n(context).backupRenamedTitle),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: plan.renamedFolders.length,
                          itemBuilder: (_, index) {
                            final entry = renamed[index];
                            final original = folderNames[entry.key]!;
                            return ListTile(
                              title: Text(original),
                              subtitle: Text(entry.value),
                            );
                          },
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n(context).close),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            child: Text(s.backupRenamedTitle),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final s = l10n(context);
      final review = controller.exportReview;
      final preview = controller.importPreview;
      final exported = controller.exported;
      final imported = controller.imported;
      final restored = controller.restoredImportSummary;
      final lease = controller.coordinator.activeTask;
      final progress = lease?.progress;
      final cancelling = lease?.cancelRequested ?? false;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            s.backupTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (controller.busy) ...[
                _text(s.backupCanLeave),
                if (controller.coordinator.isProtected)
                  const BackupProtectionNotice(),
                if (controller.documentName != null)
                  _text(controller.documentName!),
                if (preview != null && !cancelling) ...[
                  _text(s.backupPreview, heading: true),
                  _text(
                    s.backupCreatedAt(
                      DateFormat.yMd(
                        s.localeName,
                      ).add_Hm().format(preview.backup.createdAt.toLocal()),
                    ),
                  ),
                  ..._plan(context, preview),
                  _text(s.backupMerge),
                  _button(
                    s.backupConfirm,
                    controller.confirmImport,
                    'confirmBackupImport',
                  ),
                ] else ...[
                  Semantics(
                    liveRegion: true,
                    child: _text(
                      controller.picking
                          ? s.backupPicking
                          : backupStageLabel(
                              s,
                              cancelling
                                  ? BackupStage.cancelling
                                  : progress?.stage,
                            ),
                      key: const Key('backupStage'),
                    ),
                  ),
                  LinearProgressIndicator(
                    value: controller.picking ? null : progress?.fraction,
                    semanticsLabel: backupStageLabel(s, progress?.stage),
                  ),
                  const SizedBox(height: 12),
                  if (progress != null) ...[
                    _text(
                      progress.totalBytes == null
                          ? backupBytes(progress.processedBytes, s.localeName)
                          : s.backupByteProgress(
                              backupBytes(
                                progress.processedBytes,
                                s.localeName,
                              ),
                              backupBytes(progress.totalBytes!, s.localeName),
                            ),
                    ),
                    _text(
                      s.backupRecordingsCount(progress.processedRecordings),
                    ),
                  ],
                ],
                if (lease != null)
                  _button(
                    s.backupCancel,
                    cancelling || !(progress?.canCancel ?? false)
                        ? null
                        : controller.cancel,
                    'cancelBackupTask',
                  ),
              ] else if (review != null) ...[
                _text(s.backupReview, heading: true),
                _text(s.backupScope),
                _text(s.backupRecordingsCount(review.recordingCount)),
                _text(s.backupFoldersCount(review.folderCount)),
                _text(
                  s.backupSpace(
                    backupBytes(review.estimate.audioBytes, s.localeName),
                    backupBytes(review.estimate.temporaryBytes, s.localeName),
                  ),
                ),
                _text(s.backupUnencrypted),
                _button(s.backupSave, controller.startExport, 'saveBackup'),
                _button(
                  s.cancel,
                  controller.dismissReview,
                  'dismissBackupReview',
                ),
              ] else ...[
                if (controller.outcome != null)
                  Semantics(
                    liveRegion: true,
                    child: _text(
                      switch (controller.outcome!) {
                        BackupOutcome.exported => s.backupExported,
                        BackupOutcome.imported => s.backupImported,
                        BackupOutcome.cancelled => s.backupCancelled,
                        BackupOutcome.failed => s.backupFailed,
                        BackupOutcome.recoveredImport =>
                          s.backupRecoveredImport,
                        BackupOutcome.interrupted => s.backupInterrupted,
                      },
                      heading: true,
                      key: const Key('backupResult'),
                    ),
                  ),
                if (controller.outcome == BackupOutcome.failed)
                  _text(backupFailureLabel(s, controller.failure)),
                if (exported != null) ...[
                  _text(exported.document.displayName),
                  SelectableText(exported.document.uri),
                  const SizedBox(height: 12),
                  _text(s.backupRecordingsCount(exported.recordingCount)),
                  _text(s.backupFoldersCount(exported.folderCount)),
                  _text(backupBytes(exported.archiveBytes, s.localeName)),
                  _text(s.backupOutsidePhone),
                  _button(
                    s.backupShare,
                    controller.sharing || exported.cachedArchivePath == null
                        ? null
                        : controller.shareExport,
                    'shareBackup',
                  ),
                  if (controller.shareHandedOff) _text(s.backupShareHandoff),
                  if (controller.shareFailed) _text(s.backupShareFailed),
                  if (exported.cachedArchivePath == null)
                    _text(s.backupShareFailed),
                ],
                if (imported != null) ...[
                  ..._plan(context, imported.plan, result: true),
                  if (!imported.hasAdditions) _text(s.backupNoAdditions),
                  if (imported.cleanupPending) _text(s.backupCleanupPending),
                ],
                if (restored != null) ...[
                  _text(s.backupAddedResult(restored.recordings)),
                  _text(s.backupFoldersCount(restored.folders)),
                  _text(s.backupDuplicateCount(restored.duplicates)),
                  _text(s.backupConflictCount(restored.conflicts)),
                ],
                if (controller.startupFailure || controller.residualUri != null)
                  _button(
                    s.retry,
                    controller.retryRecovery,
                    'retryBackupRecovery',
                  ),
                if (controller.residualUri != null) ...[
                  _text(s.backupResidual),
                  SelectableText(controller.residualUri!),
                  const SizedBox(height: 12),
                ],
                _text(s.backupDescription),
                _text(s.backupZip64),
                _button(
                  s.backupExport,
                  controller.sharing || controller.startupFailure
                      ? null
                      : controller.reviewExport,
                  'exportBackup',
                ),
                _button(
                  s.backupImport,
                  controller.sharing || controller.startupFailure
                      ? null
                      : controller.startImport,
                  'importBackup',
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
