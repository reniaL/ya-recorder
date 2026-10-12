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
  String get resumeRecording => 'Resume recording';

  @override
  String get discard => 'Discard';

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
  String get moveToAll => 'Move to All recordings';

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
      'Deleted recordings are kept for 30 days, then automatically removed. Restored recordings return to their original folder, or to All recordings if that folder no longer exists.';

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
      'MP3 recording is unavailable. Choose M4A in Settings and try again.';

  @override
  String get aacUnavailable =>
      'AAC recording is unavailable. Choose another format in Settings and try again.';

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
}
