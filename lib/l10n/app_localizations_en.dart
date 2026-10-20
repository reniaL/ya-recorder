// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Yaya Recorder';

  @override
  String get settings => 'Settings';

  @override
  String get recordingSettingsGroup => 'Recording';

  @override
  String get appearanceSettingsGroup => 'Appearance and language';

  @override
  String get dataSettingsGroup => 'Data management';

  @override
  String get theme => 'Theme';

  @override
  String get systemTheme => 'System default';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get reading => 'Loading…';

  @override
  String get retryTheme => 'Retry loading theme';

  @override
  String get defaultFormat => 'Default recording format';

  @override
  String get formatDescription =>
      'Applies to new recordings. Existing recordings keep their format.';

  @override
  String get saving => 'Saving…';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String get selectScope => 'Choose a recording folder';

  @override
  String get allRecordings => 'All recordings';

  @override
  String get selectionResetHint =>
      'Changing or closing search, or switching folders, clears your selection.';

  @override
  String get deletedRetentionHint =>
      'Deleted recordings stay here for 30 days.';

  @override
  String get deletedRecoveryRules => 'View recovery rules';

  @override
  String get unclassified => 'Unfiled';

  @override
  String recordingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordings',
      one: '1 recording',
    );
    return '$_temp0';
  }

  @override
  String get moveRecordingTo => 'Move recording to';

  @override
  String get deleteRecordingTitle => 'Move to Recently Deleted?';

  @override
  String get deleteRecordingDescription =>
      'Deleted recordings stay in Recently Deleted and can be restored before they expire.';

  @override
  String get moveToDeleted => 'Move to Recently Deleted';

  @override
  String get discardTitle => 'Discard this recording?';

  @override
  String get discardDescription => 'This unsaved recording will be deleted.';

  @override
  String discardRecordingDuration(String duration) {
    return 'Discard this $duration recording? The unsaved audio will be deleted and cannot be recovered.';
  }

  @override
  String get resumeRecording => 'Resume recording';

  @override
  String get discard => 'Discard';

  @override
  String get endRecordingTitle => 'End this recording?';

  @override
  String get endRecordingActive =>
      'Recording continues while you choose. Save or discard it to return to your recordings.';

  @override
  String get endRecordingPaused =>
      'This recording stays paused while you choose. Save or discard it to return to your recordings.';

  @override
  String get continueRecording => 'Continue recording';

  @override
  String get keepPaused => 'Keep paused';

  @override
  String get saveAndEndRecording => 'Save and finish';

  @override
  String get searchAll => 'Search all recordings';

  @override
  String get exitSelection => 'Exit selection mode';

  @override
  String get selectRecordings => 'Select recordings';

  @override
  String get closeSearch => 'Close search';

  @override
  String get searchRecordings => 'Search recordings';

  @override
  String get more => 'More';

  @override
  String get manageFolders => 'Manage folders';

  @override
  String get recentlyDeleted => 'Recently Deleted';

  @override
  String get openSystemSettings => 'Open system settings';

  @override
  String get deselectAll => 'Deselect all';

  @override
  String get selectAll => 'Select all';

  @override
  String get move => 'Move';

  @override
  String get delete => 'Delete';

  @override
  String get startRecording => 'Start recording';

  @override
  String get requestAgain => 'Try again';

  @override
  String get reload => 'Reload';

  @override
  String get noRecordings => 'No recordings yet';

  @override
  String get noRecordingsDescription =>
      'Tap “Start recording” to make your first recording.';

  @override
  String get noMatches => 'No matching recordings';

  @override
  String get noMatchesDescription => 'Try a different search term.';

  @override
  String get pausePlayback => 'Pause playback';

  @override
  String get playRecording => 'Play recording';

  @override
  String get recordingActions => 'Recording options';

  @override
  String get rename => 'Rename';

  @override
  String get moveToFolder => 'Move to folder';

  @override
  String get share => 'Share';

  @override
  String get newRecording => 'New recording';

  @override
  String get pause => 'Pause';

  @override
  String get stopAndSave => 'Stop and save';

  @override
  String get discardRecording => 'Discard recording';

  @override
  String get recordingIdle => 'Ready to record';

  @override
  String get recordingPreparing => 'Preparing to record…';

  @override
  String get recordingActive => 'Recording';

  @override
  String get recordingPaused => 'Recording paused';

  @override
  String get recordingStopping => 'Finishing recording…';

  @override
  String get recordingDiscarding => 'Discarding recording…';

  @override
  String get recordingFailed => 'Please start a new recording';

  @override
  String get dismissMessage => 'Dismiss message';

  @override
  String get renameRecording => 'Rename recording';

  @override
  String get recordingTitle => 'Recording title';

  @override
  String get save => 'Save';

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get folderActions => 'Folder options';

  @override
  String get deleteFolder => 'Delete folder';

  @override
  String get sortFolders => 'Reorder folders';

  @override
  String get cancelSorting => 'Cancel reordering';

  @override
  String get done => 'Done';

  @override
  String get sort => 'Reorder';

  @override
  String get sortingDescription =>
      'Drag the handles on the right to reorder folders.';

  @override
  String get noFolders => 'No folders yet.';

  @override
  String get createFolder => 'Create folder';

  @override
  String get folderName => 'Folder name';

  @override
  String get create => 'Create';

  @override
  String get renameFolder => 'Rename folder';

  @override
  String get deleteFolderTitle => 'Delete this folder?';

  @override
  String get handleFolderRecordings => 'Choose where to move the recordings';

  @override
  String get moveToUnclassified => 'Move to Unfiled';

  @override
  String get close => 'Close';

  @override
  String get viewFullTitle => 'View full recording title';

  @override
  String get loadingPlayback => 'Loading…';

  @override
  String get playbackFailed => 'Playback failed';

  @override
  String get playing => 'Playing';

  @override
  String get playbackPaused => 'Paused';

  @override
  String get notPlaying => 'Not playing';

  @override
  String get retryPlayback => 'Retry playback';

  @override
  String get skipBackward => 'Skip back 5 seconds';

  @override
  String get skipForward => 'Skip forward 5 seconds';

  @override
  String get playbackSpeed => 'Playback speed';

  @override
  String get playbackProgress => 'Playback progress';

  @override
  String get permanentDeleteTitle => 'Permanently delete this recording?';

  @override
  String get permanentDelete => 'Delete permanently';

  @override
  String get deletedDescription =>
      'Deleted recordings are kept for 30 days, then automatically removed. Restored recordings return to their original folder, or become unfiled if that folder no longer exists. Find unfiled recordings in All recordings.';

  @override
  String get loadingDeleted => 'Loading Recently Deleted…';

  @override
  String get deletedEmpty => 'No recently deleted recordings';

  @override
  String get restore => 'Restore';

  @override
  String get themeReadFailed =>
      'Couldn\'t load your theme setting. Please try again.';

  @override
  String get themeSaveFailed =>
      'Couldn\'t save your theme setting. Please try again.';

  @override
  String get formatReadFailed =>
      'Couldn\'t load your recording format setting. Please try again.';

  @override
  String get formatSaveFailed =>
      'Couldn\'t save your recording format setting. Please try again.';

  @override
  String get recoveryIndexFailed =>
      'Some recordings couldn\'t be added to your library. Their audio files have been kept. You can try recovering them again later.';

  @override
  String get recoveryUnresolved =>
      'Some interrupted recordings couldn\'t be recovered. Their remaining audio files have been kept.';

  @override
  String get recoveryCheckFailed =>
      'Couldn\'t check for recordings to recover. Please reopen the app to try again.';

  @override
  String get expiredCleanupPartial =>
      'Some expired recordings couldn\'t be removed. Please try again in Recently Deleted.';

  @override
  String get expiredCleanupFailed =>
      'Couldn\'t remove expired recordings. Please try again in Recently Deleted.';

  @override
  String get openDeletedFailed => 'Couldn\'t open Recently Deleted.';

  @override
  String get openSettingsFailed => 'Couldn\'t open Settings. Please try again.';

  @override
  String get statusReadFailed => 'Couldn\'t check the recording status.';

  @override
  String get libraryReadFailed => 'Couldn\'t load your recordings.';

  @override
  String get foldersReadFailed => 'Couldn\'t load your folders.';

  @override
  String get shareFailed => 'Couldn\'t share this recording.';

  @override
  String get renameRecordingFailed => 'Couldn\'t rename this recording.';

  @override
  String get createFolderFirst => 'Create a folder before moving recordings.';

  @override
  String get moveRecordingFailed => 'Couldn\'t move this recording.';

  @override
  String get deleteRecordingFailed => 'Couldn\'t delete this recording.';

  @override
  String get batchDeleteFailed =>
      'Couldn\'t delete the selected recordings. Please try again.';

  @override
  String get batchMoveFailed =>
      'Couldn\'t move the selected recordings. Please try again.';

  @override
  String get foldersRefreshFailed => 'Couldn\'t refresh your folders.';

  @override
  String get microphoneRequired => 'Microphone access is required to record.';

  @override
  String get defaultFormatReadFailed =>
      'Couldn\'t load the default recording format. Please try again in Settings.';

  @override
  String get mp3Unavailable =>
      'MP3 recording is unavailable. Choose AAC in Settings and try again.';

  @override
  String get aacUnavailable =>
      'AAC recording is unavailable. Choose MP3 in Settings and try again.';

  @override
  String get aacFormatDescription => 'ADTS file, .aac extension';

  @override
  String get startFailed => 'Couldn\'t start recording.';

  @override
  String get startRetryFailed => 'Couldn\'t start recording. Please try again.';

  @override
  String get systemSettingsFailed => 'Couldn\'t open system settings.';

  @override
  String get recordingUpdateFailed => 'Couldn\'t update the recording state.';

  @override
  String get recordingStopFailed => 'Couldn\'t stop recording.';

  @override
  String get discardFailed => 'Couldn\'t discard this recording.';

  @override
  String get recordingDiscarded => 'Recording discarded';

  @override
  String get serviceConnectionFailed =>
      'Couldn\'t connect to the recording service.';

  @override
  String get savedCleanupPending =>
      'Recording saved. Cleanup will finish the next time you open the app.';

  @override
  String get interruptedSaved =>
      'Recording was interrupted. The captured audio has been saved.';

  @override
  String get recordingSaved => 'Recording saved';

  @override
  String get saveIndexFailed =>
      'Couldn\'t add the recording to your library. Its audio file has been kept. You can try recovering it again later.';

  @override
  String get folderOrderSaveFailed =>
      'Couldn\'t save the folder order. Please try again.';

  @override
  String get createFolderFailed =>
      'Couldn\'t create the folder. Enter a name that isn\'t empty or already in use.';

  @override
  String get renameFolderFailed =>
      'Couldn\'t rename the folder. Enter a name that isn\'t empty or already in use.';

  @override
  String get deleteFolderFailed => 'Couldn\'t delete this folder.';

  @override
  String get playbackSpeedFailed =>
      'Couldn\'t change the playback speed. Please try again.';

  @override
  String get playbackLoadFailed => 'Couldn\'t play this recording.';

  @override
  String get expiredCleanupRetry =>
      'Some expired recordings couldn\'t be removed. Please try again.';

  @override
  String get deletedReadFailed =>
      'Couldn\'t load Recently Deleted. Please try again.';

  @override
  String get recordingPermanentlyDeleted => 'Recording permanently deleted';

  @override
  String get recordingRestored => 'Recording restored';

  @override
  String get permanentDeleteFailed =>
      'Couldn\'t delete the recording permanently. It is still in Recently Deleted. Please try again.';

  @override
  String get restoreFailed =>
      'Couldn\'t restore the recording. Please try again.';

  @override
  String deleteSelectedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Move $count recordings to Recently Deleted?',
      one: 'Move 1 recording to Recently Deleted?',
    );
    return '$_temp0';
  }

  @override
  String moveSelectedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Move $count recordings to',
      one: 'Move 1 recording to',
    );
    return '$_temp0';
  }

  @override
  String selectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String searchFolder(String name) {
    return 'Search recordings in “$name”';
  }

  @override
  String switchScope(String name) {
    return '$name, change recording folder';
  }

  @override
  String selectRecording(String title) {
    return 'Select $title';
  }

  @override
  String speedValue(String speed) {
    return 'Playback speed: $speed×';
  }

  @override
  String recordingFormat(String format) {
    return 'Recording format: $format';
  }

  @override
  String moveFolderPosition(String name) {
    return 'Move $name';
  }

  @override
  String reorderFolder(String name) {
    return 'Reorder $name';
  }

  @override
  String emptyFolderDelete(String name) {
    return '“$name” is empty. Deleting this folder cannot be undone.';
  }

  @override
  String nonemptyFolderDelete(String name) {
    return '“$name” still contains recordings. Choose where to move them before deleting the folder.';
  }

  @override
  String permanentDeleteDescription(String title) {
    return 'The audio file for “$title” will be permanently deleted. This cannot be undone.';
  }

  @override
  String deletionInfo(String date, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days remaining',
      one: '1 day remaining',
    );
    return 'Deleted on $date\n$_temp0';
  }

  @override
  String titleActions(String title) {
    return 'Options for $title';
  }

  @override
  String formatUnavailable(String format) {
    return '$format is currently unavailable';
  }

  @override
  String defaultRecordingTitle(String date) {
    return 'Recording $date';
  }

  @override
  String get language => 'Language';

  @override
  String get languageReadFailed =>
      'Couldn\'t load your language setting. Please try again.';

  @override
  String get languageSaveFailed =>
      'Couldn\'t save your language setting. Please try again.';

  @override
  String get retryLanguage => 'Retry loading language';

  @override
  String get genericError => 'Something went wrong. Please try again.';

  @override
  String get recordingFormatInvalid => 'The recording format is invalid.';

  @override
  String get recordingStorageUnavailable =>
      'Recording storage is unavailable. Check your available storage and try again.';

  @override
  String get recordingInterruptedUnsaved =>
      'Recording was interrupted and couldn\'t be saved. The remaining audio files have been kept.';

  @override
  String get recordingPauseFailed =>
      'Couldn\'t pause recording. The recording was interrupted.';

  @override
  String get recordingResumeFailed =>
      'Couldn\'t resume recording. The recording was interrupted.';

  @override
  String get recordingSessionMissing =>
      'The active recording session was lost. Please check for recordings to recover.';

  @override
  String get recordingSaveFailed =>
      'Couldn\'t save the recording. The remaining audio files have been kept.';

  @override
  String get permissionRequestActive =>
      'A microphone permission request is already in progress.';

  @override
  String get shareInvalidRecording =>
      'Only completed recordings with a valid format can be shared.';

  @override
  String get recordingBaseName => 'Recording';

  @override
  String get backupTitle => 'Backup and restore';

  @override
  String get backupDescription =>
      'Export all saved recordings, or merge a backup into this library.';

  @override
  String get backupExport => 'Export backup';

  @override
  String get backupImport => 'Import backup';

  @override
  String get backupCurrentTask => 'View current task';

  @override
  String get backupLastResult => 'View last result';

  @override
  String get backupReview => 'Review export';

  @override
  String get backupPreview => 'Review import';

  @override
  String get backupScope =>
      'Includes saved recordings and all folders, including empty folders. Recently Deleted, drafts and app settings are excluded.';

  @override
  String get backupUnencrypted =>
      'This backup is not encrypted. Anyone with the file can read the audio and recording information.';

  @override
  String backupSpace(String audio, String temporary) {
    return 'Audio: $audio. Estimated temporary ZIP: up to $temporary. A local destination may need another copy of that size. Destination capacity cannot be checked in advance. The library is checked again when export starts.';
  }

  @override
  String get backupSave => 'Choose save location';

  @override
  String get backupConfirm => 'Confirm import';

  @override
  String get backupMerge =>
      'Existing recording IDs are skipped, including Recently Deleted. Existing audio and metadata will be kept. No overwrite or extra-copy options are offered.';

  @override
  String get backupProtected =>
      'A backup task is protecting your library. Recording and management changes are temporarily unavailable. You can still browse, play audio and change settings.';

  @override
  String get backupCanLeave =>
      'You can leave this page and return from Settings or the task notification. Going back does not cancel the task.';

  @override
  String get backupZip64 =>
      'ZIP64 backups and ZIP files of 4 GiB or more cannot currently be imported.';

  @override
  String get backupPreparing => 'Checking recordings';

  @override
  String get backupChecking => 'Checking backup';

  @override
  String get backupPacking => 'Packing files';

  @override
  String get backupVerifying => 'Verifying backup';

  @override
  String get backupSaving => 'Saving backup';

  @override
  String get backupImporting => 'Importing files';

  @override
  String get backupCommitting =>
      'Finishing import — cancellation is unavailable';

  @override
  String get backupCancelling => 'Cancelling safely';

  @override
  String get backupPicking =>
      'Choose a file or save location in the system picker.';

  @override
  String get backupWorking => 'Preparing task';

  @override
  String get backupCancel => 'Cancel task';

  @override
  String get backupExported => 'Backup saved';

  @override
  String get backupImported => 'Import complete';

  @override
  String get backupNoAdditions =>
      'Everything already exists. No recordings or folders were added.';

  @override
  String get backupCancelled =>
      'Task cancelled. Existing recordings are unchanged.';

  @override
  String get backupFailed => 'Task could not be completed';

  @override
  String get backupOutsidePhone =>
      'Copy this backup to a computer, external drive or other device. A backup kept only on this phone cannot protect against losing the phone.';

  @override
  String get backupShare => 'Share backup';

  @override
  String get backupShareHandoff =>
      'The backup was handed to the selected app. This does not confirm a remote upload.';

  @override
  String get backupShareFailed =>
      'Could not share the backup. Its temporary copy may have expired; export again to retry.';

  @override
  String get backupCleanupPending =>
      'The import is committed. Some task files still need cleanup; reopening the app will retry. Imported audio will be kept.';

  @override
  String get backupResidual =>
      'An unusable partial backup may remain at this location. Remove it before trying again:';

  @override
  String get backupRecoveredImport =>
      'The previous import was committed. Your imported recordings have been kept.';

  @override
  String get backupInterrupted =>
      'We can\'t confirm that the previous task finished completely. Return to your library and check your recordings and folders before exporting or importing again.';

  @override
  String get backupStatusExported => 'Backup exported';

  @override
  String get backupStatusImported => 'Import complete';

  @override
  String get backupStatusCancelled => 'Task cancelled';

  @override
  String get backupStatusFailed => 'Task incomplete';

  @override
  String get backupStatusRecovered => 'Previous import committed';

  @override
  String get backupStatusInterrupted => 'Previous task interrupted';

  @override
  String get returnToLibrary => 'Return to library';

  @override
  String get backupErrorBusy =>
      'Finish recording or other library changes before starting a backup task.';

  @override
  String get backupErrorInvalid =>
      'The backup is damaged or invalid. No backup content was imported.';

  @override
  String get backupErrorVersion =>
      'This backup version is not supported. Use a compatible app version.';

  @override
  String get backupErrorSpace =>
      'There is not enough storage. Free space in the app storage and save location, then try again.';

  @override
  String get backupErrorPermission =>
      'File access was denied or expired. Select the file or save location again.';

  @override
  String get backupErrorLocal =>
      'Existing audio or a target path is inconsistent. Existing files were kept. Check your library before retrying.';

  @override
  String get backupErrorCleanup =>
      'Task cleanup could not finish. Files with uncertain ownership were kept. Reopen the app to retry recovery.';

  @override
  String get backupErrorStartup =>
      'The backup task could not start. Return to the app and try again. Existing recordings were kept.';

  @override
  String get backupErrorUnknown =>
      'The task could not be completed. Try again. If it keeps failing, keep a note of the steps for troubleshooting. Existing recordings were kept.';

  @override
  String get backupRenamedTitle => 'Folder names changed for import';

  @override
  String backupCreatedAt(String date) {
    return 'Backup created: $date';
  }

  @override
  String backupByteProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String backupRecordingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordings',
      one: '1 recording',
      zero: '0 recordings',
    );
    return '$_temp0';
  }

  @override
  String backupFoldersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folders',
      one: '1 folder',
      zero: '0 folders',
    );
    return '$_temp0';
  }

  @override
  String backupAddedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordings to add',
      one: '1 recording to add',
      zero: '0 recordings to add',
    );
    return '$_temp0';
  }

  @override
  String backupDuplicateCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count duplicates skipped',
      one: '1 duplicate skipped',
      zero: '0 duplicates skipped',
    );
    return '$_temp0';
  }

  @override
  String backupConflictCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conflicting recordings skipped',
      one: '1 conflicting recording skipped',
      zero: '0 conflicting recordings skipped',
    );
    return '$_temp0';
  }

  @override
  String backupAddedResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordings added',
      one: '1 recording added',
      zero: '0 recordings added',
    );
    return '$_temp0';
  }
}
