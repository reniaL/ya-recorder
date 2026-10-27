import 'package:flutter/widgets.dart';
import 'app_localizations.dart';
import 'app_localizations_zh.dart';
export 'app_localizations.dart';

String nativeMessageCode(String code, {String fallback = 'genericError'}) =>
    switch (code) {
      'recording-format-invalid' => 'recordingFormatInvalid',
      'recording-format-unavailable' => 'mp3Unavailable',
      'storage-unavailable' => 'recordingStorageUnavailable',
      'recording-runtime-failed' => 'recordingInterruptedUnsaved',
      'recording-start-failed' => 'startFailed',
      'recording-pause-failed' => 'recordingPauseFailed',
      'recording-resume-failed' => 'recordingResumeFailed',
      'recording-session-missing' => 'recordingSessionMissing',
      'recording-save-failed' => 'recordingSaveFailed',
      'recording-cancel-failed' => 'discardFailed',
      'microphone-permission-required' => 'microphoneRequired',
      'permission-request-in-progress' => 'permissionRequestActive',
      'app-settings-unavailable' => 'systemSettingsFailed',
      _ => fallback,
    };

// Standalone widgets retain the app's Chinese default without a delegate.
AppLocalizations l10n(BuildContext context) =>
    Localizations.of<AppLocalizations>(context, AppLocalizations) ??
    AppLocalizationsZh();

/// Resolve transient message identifiers at render time, so visible errors and
/// notices switch language too. Native diagnostics are never shown verbatim.
String localizedMessage(BuildContext context, String identifier) {
  final strings = l10n(context);
  return switch (identifier) {
    'aacUnavailable' => strings.aacUnavailable,
    'themeReadFailed' => strings.themeReadFailed,
    'paletteReadFailed' => strings.paletteReadFailed,
    'paletteSaveFailed' => strings.paletteSaveFailed,
    'themeSaveFailed' => strings.themeSaveFailed,
    'formatReadFailed' => strings.formatReadFailed,
    'formatSaveFailed' => strings.formatSaveFailed,
    'recoveryIndexFailed' => strings.recoveryIndexFailed,
    'recoveryUnresolved' => strings.recoveryUnresolved,
    'recoveryCheckFailed' => strings.recoveryCheckFailed,
    'expiredCleanupPartial' => strings.expiredCleanupPartial,
    'expiredCleanupFailed' => strings.expiredCleanupFailed,
    'openDeletedFailed' => strings.openDeletedFailed,
    'openSettingsFailed' => strings.openSettingsFailed,
    'statusReadFailed' => strings.statusReadFailed,
    'libraryReadFailed' => strings.libraryReadFailed,
    'foldersReadFailed' => strings.foldersReadFailed,
    'shareFailed' => strings.shareFailed,
    'renameRecordingFailed' => strings.renameRecordingFailed,
    'createFolderFirst' => strings.createFolderFirst,
    'moveRecordingFailed' => strings.moveRecordingFailed,
    'deleteRecordingFailed' => strings.deleteRecordingFailed,
    'batchDeleteFailed' => strings.batchDeleteFailed,
    'batchMoveFailed' => strings.batchMoveFailed,
    'foldersRefreshFailed' => strings.foldersRefreshFailed,
    'microphoneRequired' => strings.microphoneRequired,
    'defaultFormatReadFailed' => strings.defaultFormatReadFailed,
    'mp3Unavailable' || "无法开始 MP3 录音，请在设置中选择 M4A 后重试" => strings.mp3Unavailable,
    'startFailed' => strings.startFailed,
    'startRetryFailed' => strings.startRetryFailed,
    'systemSettingsFailed' => strings.systemSettingsFailed,
    'recordingUpdateFailed' => strings.recordingUpdateFailed,
    'recordingStopFailed' => strings.recordingStopFailed,
    'discardFailed' => strings.discardFailed,
    'recordingDiscarded' => strings.recordingDiscarded,
    'serviceConnectionFailed' => strings.serviceConnectionFailed,
    'savedCleanupPending' => strings.savedCleanupPending,
    'interruptedSaved' => strings.interruptedSaved,
    'recordingSaved' => strings.recordingSaved,
    'recordingFolderMissing' => strings.recordingFolderMissing,
    'interruptedFolderMissing' => strings.interruptedFolderMissing,
    'saveIndexFailed' => strings.saveIndexFailed,
    'folderOrderSaveFailed' => strings.folderOrderSaveFailed,
    'createFolderFailed' => strings.createFolderFailed,
    'renameFolderFailed' => strings.renameFolderFailed,
    'deleteFolderFailed' => strings.deleteFolderFailed,
    'playbackSpeedFailed' => strings.playbackSpeedFailed,
    'playbackLoadFailed' => strings.playbackLoadFailed,
    'expiredCleanupRetry' => strings.expiredCleanupRetry,
    'deletedReadFailed' => strings.deletedReadFailed,
    'recordingPermanentlyDeleted' => strings.recordingPermanentlyDeleted,
    'recordingRestored' => strings.recordingRestored,
    'permanentDeleteFailed' => strings.permanentDeleteFailed,
    'restoreFailed' => strings.restoreFailed,
    'languageReadFailed' => strings.languageReadFailed,
    'languageSaveFailed' => strings.languageSaveFailed,
    'genericError' => strings.genericError,
    'recordingFormatInvalid' => strings.recordingFormatInvalid,
    'recordingStorageUnavailable' => strings.recordingStorageUnavailable,
    'recordingInterruptedUnsaved' => strings.recordingInterruptedUnsaved,
    'recordingPauseFailed' => strings.recordingPauseFailed,
    'recordingResumeFailed' => strings.recordingResumeFailed,
    'recordingSessionMissing' => strings.recordingSessionMissing,
    'recordingSaveFailed' => strings.recordingSaveFailed,
    'permissionRequestActive' => strings.permissionRequestActive,
    'shareInvalidRecording' => strings.shareInvalidRecording,
    _ => strings.genericError,
  };
}
