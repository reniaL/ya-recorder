import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Yaya Recorder'**
  String get appTitle;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @systemTheme.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemTheme;

  /// No description provided for @lightTheme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightTheme;

  /// No description provided for @darkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkTheme;

  /// No description provided for @reading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get reading;

  /// No description provided for @retryTheme.
  ///
  /// In en, this message translates to:
  /// **'Retry loading theme'**
  String get retryTheme;

  /// No description provided for @defaultFormat.
  ///
  /// In en, this message translates to:
  /// **'Default recording format'**
  String get defaultFormat;

  /// No description provided for @formatDescription.
  ///
  /// In en, this message translates to:
  /// **'Applies to new recordings. Existing recordings keep their format.'**
  String get formatDescription;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @selectScope.
  ///
  /// In en, this message translates to:
  /// **'Choose a recording folder'**
  String get selectScope;

  /// No description provided for @allRecordings.
  ///
  /// In en, this message translates to:
  /// **'All recordings'**
  String get allRecordings;

  /// No description provided for @unclassified.
  ///
  /// In en, this message translates to:
  /// **'Unfiled'**
  String get unclassified;

  /// No description provided for @recordingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recording} other{{count} recordings}}'**
  String recordingCount(int count);

  /// No description provided for @moveRecordingTo.
  ///
  /// In en, this message translates to:
  /// **'Move recording to'**
  String get moveRecordingTo;

  /// No description provided for @deleteRecordingTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to Recently Deleted?'**
  String get deleteRecordingTitle;

  /// No description provided for @deleteRecordingDescription.
  ///
  /// In en, this message translates to:
  /// **'Deleted recordings stay in Recently Deleted and can be restored before they expire.'**
  String get deleteRecordingDescription;

  /// No description provided for @moveToDeleted.
  ///
  /// In en, this message translates to:
  /// **'Move to Recently Deleted'**
  String get moveToDeleted;

  /// No description provided for @discardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard this recording?'**
  String get discardTitle;

  /// No description provided for @discardDescription.
  ///
  /// In en, this message translates to:
  /// **'This unsaved recording will be deleted.'**
  String get discardDescription;

  /// No description provided for @discardRecordingDuration.
  ///
  /// In en, this message translates to:
  /// **'Discard this {duration} recording? The unsaved audio will be deleted and cannot be recovered.'**
  String discardRecordingDuration(String duration);

  /// No description provided for @resumeRecording.
  ///
  /// In en, this message translates to:
  /// **'Resume recording'**
  String get resumeRecording;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @endRecordingTitle.
  ///
  /// In en, this message translates to:
  /// **'End this recording?'**
  String get endRecordingTitle;

  /// No description provided for @endRecordingActive.
  ///
  /// In en, this message translates to:
  /// **'Recording continues while you choose. Save or discard it to return to your recordings.'**
  String get endRecordingActive;

  /// No description provided for @endRecordingPaused.
  ///
  /// In en, this message translates to:
  /// **'This recording stays paused while you choose. Save or discard it to return to your recordings.'**
  String get endRecordingPaused;

  /// No description provided for @continueRecording.
  ///
  /// In en, this message translates to:
  /// **'Continue recording'**
  String get continueRecording;

  /// No description provided for @keepPaused.
  ///
  /// In en, this message translates to:
  /// **'Keep paused'**
  String get keepPaused;

  /// No description provided for @saveAndEndRecording.
  ///
  /// In en, this message translates to:
  /// **'Save and finish'**
  String get saveAndEndRecording;

  /// No description provided for @searchAll.
  ///
  /// In en, this message translates to:
  /// **'Search all recordings'**
  String get searchAll;

  /// No description provided for @exitSelection.
  ///
  /// In en, this message translates to:
  /// **'Exit selection mode'**
  String get exitSelection;

  /// No description provided for @selectRecordings.
  ///
  /// In en, this message translates to:
  /// **'Select recordings'**
  String get selectRecordings;

  /// No description provided for @closeSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearch;

  /// No description provided for @searchRecordings.
  ///
  /// In en, this message translates to:
  /// **'Search recordings'**
  String get searchRecordings;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @manageFolders.
  ///
  /// In en, this message translates to:
  /// **'Manage folders'**
  String get manageFolders;

  /// No description provided for @recentlyDeleted.
  ///
  /// In en, this message translates to:
  /// **'Recently Deleted'**
  String get recentlyDeleted;

  /// No description provided for @openSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Open system settings'**
  String get openSystemSettings;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get deselectAll;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @move.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get move;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @startRecording.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get startRecording;

  /// No description provided for @requestAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get requestAgain;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @noRecordings.
  ///
  /// In en, this message translates to:
  /// **'No recordings yet'**
  String get noRecordings;

  /// No description provided for @noRecordingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Tap “Start recording” to make your first recording.'**
  String get noRecordingsDescription;

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'No matching recordings'**
  String get noMatches;

  /// No description provided for @noMatchesDescription.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term.'**
  String get noMatchesDescription;

  /// No description provided for @pausePlayback.
  ///
  /// In en, this message translates to:
  /// **'Pause playback'**
  String get pausePlayback;

  /// No description provided for @playRecording.
  ///
  /// In en, this message translates to:
  /// **'Play recording'**
  String get playRecording;

  /// No description provided for @recordingActions.
  ///
  /// In en, this message translates to:
  /// **'Recording options'**
  String get recordingActions;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @moveToFolder.
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get moveToFolder;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @newRecording.
  ///
  /// In en, this message translates to:
  /// **'New recording'**
  String get newRecording;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @stopAndSave.
  ///
  /// In en, this message translates to:
  /// **'Stop and save'**
  String get stopAndSave;

  /// No description provided for @discardRecording.
  ///
  /// In en, this message translates to:
  /// **'Discard recording'**
  String get discardRecording;

  /// No description provided for @recordingIdle.
  ///
  /// In en, this message translates to:
  /// **'Ready to record'**
  String get recordingIdle;

  /// No description provided for @recordingPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing to record…'**
  String get recordingPreparing;

  /// No description provided for @recordingActive.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get recordingActive;

  /// No description provided for @recordingPaused.
  ///
  /// In en, this message translates to:
  /// **'Recording paused'**
  String get recordingPaused;

  /// No description provided for @recordingStopping.
  ///
  /// In en, this message translates to:
  /// **'Finishing recording…'**
  String get recordingStopping;

  /// No description provided for @recordingDiscarding.
  ///
  /// In en, this message translates to:
  /// **'Discarding recording…'**
  String get recordingDiscarding;

  /// No description provided for @recordingFailed.
  ///
  /// In en, this message translates to:
  /// **'Please start a new recording'**
  String get recordingFailed;

  /// No description provided for @dismissMessage.
  ///
  /// In en, this message translates to:
  /// **'Dismiss message'**
  String get dismissMessage;

  /// No description provided for @renameRecording.
  ///
  /// In en, this message translates to:
  /// **'Rename recording'**
  String get renameRecording;

  /// No description provided for @recordingTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording title'**
  String get recordingTitle;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDown;

  /// No description provided for @folderActions.
  ///
  /// In en, this message translates to:
  /// **'Folder options'**
  String get folderActions;

  /// No description provided for @deleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete folder'**
  String get deleteFolder;

  /// No description provided for @sortFolders.
  ///
  /// In en, this message translates to:
  /// **'Reorder folders'**
  String get sortFolders;

  /// No description provided for @cancelSorting.
  ///
  /// In en, this message translates to:
  /// **'Cancel reordering'**
  String get cancelSorting;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get sort;

  /// No description provided for @sortingDescription.
  ///
  /// In en, this message translates to:
  /// **'Drag the handles on the right to reorder folders.'**
  String get sortingDescription;

  /// No description provided for @noFolders.
  ///
  /// In en, this message translates to:
  /// **'No folders yet.'**
  String get noFolders;

  /// No description provided for @createFolder.
  ///
  /// In en, this message translates to:
  /// **'Create folder'**
  String get createFolder;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @renameFolder.
  ///
  /// In en, this message translates to:
  /// **'Rename folder'**
  String get renameFolder;

  /// No description provided for @deleteFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this folder?'**
  String get deleteFolderTitle;

  /// No description provided for @handleFolderRecordings.
  ///
  /// In en, this message translates to:
  /// **'Choose where to move the recordings'**
  String get handleFolderRecordings;

  /// No description provided for @moveToUnclassified.
  ///
  /// In en, this message translates to:
  /// **'Move to Unfiled'**
  String get moveToUnclassified;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @viewFullTitle.
  ///
  /// In en, this message translates to:
  /// **'View full recording title'**
  String get viewFullTitle;

  /// No description provided for @loadingPlayback.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loadingPlayback;

  /// No description provided for @playbackFailed.
  ///
  /// In en, this message translates to:
  /// **'Playback failed'**
  String get playbackFailed;

  /// No description provided for @playing.
  ///
  /// In en, this message translates to:
  /// **'Playing'**
  String get playing;

  /// No description provided for @playbackPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get playbackPaused;

  /// No description provided for @notPlaying.
  ///
  /// In en, this message translates to:
  /// **'Not playing'**
  String get notPlaying;

  /// No description provided for @retryPlayback.
  ///
  /// In en, this message translates to:
  /// **'Retry playback'**
  String get retryPlayback;

  /// No description provided for @skipBackward.
  ///
  /// In en, this message translates to:
  /// **'Skip back 5 seconds'**
  String get skipBackward;

  /// No description provided for @skipForward.
  ///
  /// In en, this message translates to:
  /// **'Skip forward 5 seconds'**
  String get skipForward;

  /// No description provided for @playbackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get playbackSpeed;

  /// No description provided for @playbackProgress.
  ///
  /// In en, this message translates to:
  /// **'Playback progress'**
  String get playbackProgress;

  /// No description provided for @permanentDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete this recording?'**
  String get permanentDeleteTitle;

  /// No description provided for @permanentDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get permanentDelete;

  /// No description provided for @deletedDescription.
  ///
  /// In en, this message translates to:
  /// **'Deleted recordings are kept for 30 days, then automatically removed. Restored recordings return to their original folder, or become unfiled if that folder no longer exists. Find unfiled recordings in All recordings.'**
  String get deletedDescription;

  /// No description provided for @loadingDeleted.
  ///
  /// In en, this message translates to:
  /// **'Loading Recently Deleted…'**
  String get loadingDeleted;

  /// No description provided for @deletedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recently deleted recordings'**
  String get deletedEmpty;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @themeReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your theme setting. Please try again.'**
  String get themeReadFailed;

  /// No description provided for @themeSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your theme setting. Please try again.'**
  String get themeSaveFailed;

  /// No description provided for @formatReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your recording format setting. Please try again.'**
  String get formatReadFailed;

  /// No description provided for @formatSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your recording format setting. Please try again.'**
  String get formatSaveFailed;

  /// No description provided for @recoveryIndexFailed.
  ///
  /// In en, this message translates to:
  /// **'Some recordings couldn\'t be added to your library. Their audio files have been kept. You can try recovering them again later.'**
  String get recoveryIndexFailed;

  /// No description provided for @recoveryUnresolved.
  ///
  /// In en, this message translates to:
  /// **'Some interrupted recordings couldn\'t be recovered. Their remaining audio files have been kept.'**
  String get recoveryUnresolved;

  /// No description provided for @recoveryCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for recordings to recover. Please reopen the app to try again.'**
  String get recoveryCheckFailed;

  /// No description provided for @expiredCleanupPartial.
  ///
  /// In en, this message translates to:
  /// **'Some expired recordings couldn\'t be removed. Please try again in Recently Deleted.'**
  String get expiredCleanupPartial;

  /// No description provided for @expiredCleanupFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove expired recordings. Please try again in Recently Deleted.'**
  String get expiredCleanupFailed;

  /// No description provided for @openDeletedFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open Recently Deleted.'**
  String get openDeletedFailed;

  /// No description provided for @openSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open Settings. Please try again.'**
  String get openSettingsFailed;

  /// No description provided for @statusReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check the recording status.'**
  String get statusReadFailed;

  /// No description provided for @libraryReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your recordings.'**
  String get libraryReadFailed;

  /// No description provided for @foldersReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your folders.'**
  String get foldersReadFailed;

  /// No description provided for @shareFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share this recording.'**
  String get shareFailed;

  /// No description provided for @renameRecordingFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t rename this recording.'**
  String get renameRecordingFailed;

  /// No description provided for @createFolderFirst.
  ///
  /// In en, this message translates to:
  /// **'Create a folder before moving recordings.'**
  String get createFolderFirst;

  /// No description provided for @moveRecordingFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t move this recording.'**
  String get moveRecordingFailed;

  /// No description provided for @deleteRecordingFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete this recording.'**
  String get deleteRecordingFailed;

  /// No description provided for @batchDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the selected recordings. Please try again.'**
  String get batchDeleteFailed;

  /// No description provided for @batchMoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t move the selected recordings. Please try again.'**
  String get batchMoveFailed;

  /// No description provided for @foldersRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh your folders.'**
  String get foldersRefreshFailed;

  /// No description provided for @microphoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Microphone access is required to record.'**
  String get microphoneRequired;

  /// No description provided for @defaultFormatReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the default recording format. Please try again in Settings.'**
  String get defaultFormatReadFailed;

  /// No description provided for @mp3Unavailable.
  ///
  /// In en, this message translates to:
  /// **'MP3 recording is unavailable. Choose AAC in Settings and try again.'**
  String get mp3Unavailable;

  /// No description provided for @aacUnavailable.
  ///
  /// In en, this message translates to:
  /// **'AAC recording is unavailable. Choose MP3 in Settings and try again.'**
  String get aacUnavailable;

  /// No description provided for @aacFormatDescription.
  ///
  /// In en, this message translates to:
  /// **'ADTS file, .aac extension'**
  String get aacFormatDescription;

  /// No description provided for @startFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start recording.'**
  String get startFailed;

  /// No description provided for @startRetryFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start recording. Please try again.'**
  String get startRetryFailed;

  /// No description provided for @systemSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open system settings.'**
  String get systemSettingsFailed;

  /// No description provided for @recordingUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update the recording state.'**
  String get recordingUpdateFailed;

  /// No description provided for @recordingStopFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t stop recording.'**
  String get recordingStopFailed;

  /// No description provided for @discardFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t discard this recording.'**
  String get discardFailed;

  /// No description provided for @recordingDiscarded.
  ///
  /// In en, this message translates to:
  /// **'Recording discarded'**
  String get recordingDiscarded;

  /// No description provided for @serviceConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect to the recording service.'**
  String get serviceConnectionFailed;

  /// No description provided for @savedCleanupPending.
  ///
  /// In en, this message translates to:
  /// **'Recording saved. Cleanup will finish the next time you open the app.'**
  String get savedCleanupPending;

  /// No description provided for @interruptedSaved.
  ///
  /// In en, this message translates to:
  /// **'Recording was interrupted. The captured audio has been saved.'**
  String get interruptedSaved;

  /// No description provided for @recordingSaved.
  ///
  /// In en, this message translates to:
  /// **'Recording saved'**
  String get recordingSaved;

  /// No description provided for @saveIndexFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add the recording to your library. Its audio file has been kept. You can try recovering it again later.'**
  String get saveIndexFailed;

  /// No description provided for @folderOrderSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the folder order. Please try again.'**
  String get folderOrderSaveFailed;

  /// No description provided for @createFolderFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the folder. Enter a name that isn\'t empty or already in use.'**
  String get createFolderFailed;

  /// No description provided for @renameFolderFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t rename the folder. Enter a name that isn\'t empty or already in use.'**
  String get renameFolderFailed;

  /// No description provided for @deleteFolderFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete this folder.'**
  String get deleteFolderFailed;

  /// No description provided for @playbackSpeedFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change the playback speed. Please try again.'**
  String get playbackSpeedFailed;

  /// No description provided for @playbackLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t play this recording.'**
  String get playbackLoadFailed;

  /// No description provided for @expiredCleanupRetry.
  ///
  /// In en, this message translates to:
  /// **'Some expired recordings couldn\'t be removed. Please try again.'**
  String get expiredCleanupRetry;

  /// No description provided for @deletedReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load Recently Deleted. Please try again.'**
  String get deletedReadFailed;

  /// No description provided for @recordingPermanentlyDeleted.
  ///
  /// In en, this message translates to:
  /// **'Recording permanently deleted'**
  String get recordingPermanentlyDeleted;

  /// No description provided for @recordingRestored.
  ///
  /// In en, this message translates to:
  /// **'Recording restored'**
  String get recordingRestored;

  /// No description provided for @permanentDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the recording permanently. It is still in Recently Deleted. Please try again.'**
  String get permanentDeleteFailed;

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t restore the recording. Please try again.'**
  String get restoreFailed;

  /// No description provided for @deleteSelectedTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Move 1 recording to Recently Deleted?} other{Move {count} recordings to Recently Deleted?}}'**
  String deleteSelectedTitle(int count);

  /// No description provided for @moveSelectedTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Move 1 recording to} other{Move {count} recordings to}}'**
  String moveSelectedTitle(int count);

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected} other{{count} selected}}'**
  String selectedCount(int count);

  /// No description provided for @searchFolder.
  ///
  /// In en, this message translates to:
  /// **'Search recordings in “{name}”'**
  String searchFolder(String name);

  /// No description provided for @switchScope.
  ///
  /// In en, this message translates to:
  /// **'{name}, change recording folder'**
  String switchScope(String name);

  /// No description provided for @selectRecording.
  ///
  /// In en, this message translates to:
  /// **'Select {title}'**
  String selectRecording(String title);

  /// No description provided for @speedValue.
  ///
  /// In en, this message translates to:
  /// **'Playback speed: {speed}×'**
  String speedValue(String speed);

  /// No description provided for @recordingFormat.
  ///
  /// In en, this message translates to:
  /// **'Recording format: {format}'**
  String recordingFormat(String format);

  /// No description provided for @moveFolderPosition.
  ///
  /// In en, this message translates to:
  /// **'Move {name}'**
  String moveFolderPosition(String name);

  /// No description provided for @reorderFolder.
  ///
  /// In en, this message translates to:
  /// **'Reorder {name}'**
  String reorderFolder(String name);

  /// No description provided for @emptyFolderDelete.
  ///
  /// In en, this message translates to:
  /// **'“{name}” is empty. Deleting this folder cannot be undone.'**
  String emptyFolderDelete(String name);

  /// No description provided for @nonemptyFolderDelete.
  ///
  /// In en, this message translates to:
  /// **'“{name}” still contains recordings. Choose where to move them before deleting the folder.'**
  String nonemptyFolderDelete(String name);

  /// No description provided for @permanentDeleteDescription.
  ///
  /// In en, this message translates to:
  /// **'The audio file for “{title}” will be permanently deleted. This cannot be undone.'**
  String permanentDeleteDescription(String title);

  /// No description provided for @deletionInfo.
  ///
  /// In en, this message translates to:
  /// **'Deleted on {date}\n{days, plural, =1{1 day remaining} other{{days} days remaining}}'**
  String deletionInfo(String date, int days);

  /// No description provided for @titleActions.
  ///
  /// In en, this message translates to:
  /// **'Options for {title}'**
  String titleActions(String title);

  /// No description provided for @formatUnavailable.
  ///
  /// In en, this message translates to:
  /// **'{format} is currently unavailable'**
  String formatUnavailable(String format);

  /// No description provided for @defaultRecordingTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording {date}'**
  String defaultRecordingTitle(String date);

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your language setting. Please try again.'**
  String get languageReadFailed;

  /// No description provided for @languageSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your language setting. Please try again.'**
  String get languageSaveFailed;

  /// No description provided for @retryLanguage.
  ///
  /// In en, this message translates to:
  /// **'Retry loading language'**
  String get retryLanguage;

  /// No description provided for @genericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get genericError;

  /// No description provided for @recordingFormatInvalid.
  ///
  /// In en, this message translates to:
  /// **'The recording format is invalid.'**
  String get recordingFormatInvalid;

  /// No description provided for @recordingStorageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Recording storage is unavailable. Check your available storage and try again.'**
  String get recordingStorageUnavailable;

  /// No description provided for @recordingInterruptedUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Recording was interrupted and couldn\'t be saved. The remaining audio files have been kept.'**
  String get recordingInterruptedUnsaved;

  /// No description provided for @recordingPauseFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t pause recording. The recording was interrupted.'**
  String get recordingPauseFailed;

  /// No description provided for @recordingResumeFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t resume recording. The recording was interrupted.'**
  String get recordingResumeFailed;

  /// No description provided for @recordingSessionMissing.
  ///
  /// In en, this message translates to:
  /// **'The active recording session was lost. Please check for recordings to recover.'**
  String get recordingSessionMissing;

  /// No description provided for @recordingSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the recording. The remaining audio files have been kept.'**
  String get recordingSaveFailed;

  /// No description provided for @permissionRequestActive.
  ///
  /// In en, this message translates to:
  /// **'A microphone permission request is already in progress.'**
  String get permissionRequestActive;

  /// No description provided for @shareInvalidRecording.
  ///
  /// In en, this message translates to:
  /// **'Only completed recordings with a valid format can be shared.'**
  String get shareInvalidRecording;

  /// No description provided for @recordingBaseName.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get recordingBaseName;

  /// No description provided for @backupTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup and restore'**
  String get backupTitle;

  /// No description provided for @backupDescription.
  ///
  /// In en, this message translates to:
  /// **'Export all saved recordings, or merge a backup into this library.'**
  String get backupDescription;

  /// No description provided for @backupExport.
  ///
  /// In en, this message translates to:
  /// **'Export backup'**
  String get backupExport;

  /// No description provided for @backupImport.
  ///
  /// In en, this message translates to:
  /// **'Import backup'**
  String get backupImport;

  /// No description provided for @backupCurrentTask.
  ///
  /// In en, this message translates to:
  /// **'View current task'**
  String get backupCurrentTask;

  /// No description provided for @backupLastResult.
  ///
  /// In en, this message translates to:
  /// **'View last result'**
  String get backupLastResult;

  /// No description provided for @backupReview.
  ///
  /// In en, this message translates to:
  /// **'Review export'**
  String get backupReview;

  /// No description provided for @backupPreview.
  ///
  /// In en, this message translates to:
  /// **'Review import'**
  String get backupPreview;

  /// No description provided for @backupScope.
  ///
  /// In en, this message translates to:
  /// **'Includes saved recordings and all folders, including empty folders. Recently Deleted, drafts and app settings are excluded.'**
  String get backupScope;

  /// No description provided for @backupUnencrypted.
  ///
  /// In en, this message translates to:
  /// **'This backup is not encrypted. Anyone with the file can read the audio and recording information.'**
  String get backupUnencrypted;

  /// No description provided for @backupSpace.
  ///
  /// In en, this message translates to:
  /// **'Audio: {audio}. Estimated temporary ZIP: up to {temporary}. A local destination may need another copy of that size. Destination capacity cannot be checked in advance. The library is checked again when export starts.'**
  String backupSpace(String audio, String temporary);

  /// No description provided for @backupSave.
  ///
  /// In en, this message translates to:
  /// **'Choose save location'**
  String get backupSave;

  /// No description provided for @backupConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm import'**
  String get backupConfirm;

  /// No description provided for @backupMerge.
  ///
  /// In en, this message translates to:
  /// **'Existing recording IDs are skipped, including Recently Deleted. Existing audio and metadata will be kept. No overwrite or extra-copy options are offered.'**
  String get backupMerge;

  /// No description provided for @backupProtected.
  ///
  /// In en, this message translates to:
  /// **'A backup task is protecting your library. Recording and management changes are temporarily unavailable. You can still browse, play audio and change settings.'**
  String get backupProtected;

  /// No description provided for @backupCanLeave.
  ///
  /// In en, this message translates to:
  /// **'You can leave this page and return from Settings or the task notification. Going back does not cancel the task.'**
  String get backupCanLeave;

  /// No description provided for @backupZip64.
  ///
  /// In en, this message translates to:
  /// **'ZIP64 backups and ZIP files of 4 GiB or more cannot currently be imported.'**
  String get backupZip64;

  /// No description provided for @backupPreparing.
  ///
  /// In en, this message translates to:
  /// **'Checking recordings'**
  String get backupPreparing;

  /// No description provided for @backupChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking backup'**
  String get backupChecking;

  /// No description provided for @backupPacking.
  ///
  /// In en, this message translates to:
  /// **'Packing files'**
  String get backupPacking;

  /// No description provided for @backupVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying backup'**
  String get backupVerifying;

  /// No description provided for @backupSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving backup'**
  String get backupSaving;

  /// No description provided for @backupImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing files'**
  String get backupImporting;

  /// No description provided for @backupCommitting.
  ///
  /// In en, this message translates to:
  /// **'Finishing import — cancellation is unavailable'**
  String get backupCommitting;

  /// No description provided for @backupCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling safely'**
  String get backupCancelling;

  /// No description provided for @backupPicking.
  ///
  /// In en, this message translates to:
  /// **'Choose a file or save location in the system picker.'**
  String get backupPicking;

  /// No description provided for @backupWorking.
  ///
  /// In en, this message translates to:
  /// **'Preparing task'**
  String get backupWorking;

  /// No description provided for @backupCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel task'**
  String get backupCancel;

  /// No description provided for @backupExported.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get backupExported;

  /// No description provided for @backupImported.
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get backupImported;

  /// No description provided for @backupNoAdditions.
  ///
  /// In en, this message translates to:
  /// **'Everything already exists. No recordings or folders were added.'**
  String get backupNoAdditions;

  /// No description provided for @backupCancelled.
  ///
  /// In en, this message translates to:
  /// **'Task cancelled. Existing recordings are unchanged.'**
  String get backupCancelled;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Task could not be completed'**
  String get backupFailed;

  /// No description provided for @backupOutsidePhone.
  ///
  /// In en, this message translates to:
  /// **'Copy this backup to a computer, external drive or other device. A backup kept only on this phone cannot protect against losing the phone.'**
  String get backupOutsidePhone;

  /// No description provided for @backupShare.
  ///
  /// In en, this message translates to:
  /// **'Share backup'**
  String get backupShare;

  /// No description provided for @backupShareHandoff.
  ///
  /// In en, this message translates to:
  /// **'The backup was handed to the selected app. This does not confirm a remote upload.'**
  String get backupShareHandoff;

  /// No description provided for @backupShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not share the backup. Its temporary copy may have expired; export again to retry.'**
  String get backupShareFailed;

  /// No description provided for @backupCleanupPending.
  ///
  /// In en, this message translates to:
  /// **'The import is committed. Some task files still need cleanup; reopening the app will retry. Imported audio will be kept.'**
  String get backupCleanupPending;

  /// No description provided for @backupResidual.
  ///
  /// In en, this message translates to:
  /// **'An unusable partial backup may remain at this location. Remove it before trying again:'**
  String get backupResidual;

  /// No description provided for @backupRecoveredImport.
  ///
  /// In en, this message translates to:
  /// **'The previous import was committed. Your imported recordings have been kept.'**
  String get backupRecoveredImport;

  /// No description provided for @backupInterrupted.
  ///
  /// In en, this message translates to:
  /// **'The previous task stopped unexpectedly. Startup recovery has run. Check your recording library before trying again.'**
  String get backupInterrupted;

  /// No description provided for @backupErrorBusy.
  ///
  /// In en, this message translates to:
  /// **'Finish recording or other library changes before starting a backup task.'**
  String get backupErrorBusy;

  /// No description provided for @backupErrorInvalid.
  ///
  /// In en, this message translates to:
  /// **'The backup is damaged or invalid. No backup content was imported.'**
  String get backupErrorInvalid;

  /// No description provided for @backupErrorVersion.
  ///
  /// In en, this message translates to:
  /// **'This backup version is not supported. Use a compatible app version.'**
  String get backupErrorVersion;

  /// No description provided for @backupErrorSpace.
  ///
  /// In en, this message translates to:
  /// **'There is not enough storage. Free space in the app storage and save location, then try again.'**
  String get backupErrorSpace;

  /// No description provided for @backupErrorPermission.
  ///
  /// In en, this message translates to:
  /// **'File access was denied or expired. Select the file or save location again.'**
  String get backupErrorPermission;

  /// No description provided for @backupErrorLocal.
  ///
  /// In en, this message translates to:
  /// **'Existing audio or a target path is inconsistent. Existing files were kept. Check your library before retrying.'**
  String get backupErrorLocal;

  /// No description provided for @backupErrorCleanup.
  ///
  /// In en, this message translates to:
  /// **'Task cleanup could not finish. Files with uncertain ownership were kept. Reopen the app to retry recovery.'**
  String get backupErrorCleanup;

  /// No description provided for @backupErrorStartup.
  ///
  /// In en, this message translates to:
  /// **'The backup task could not start. Return to the app and try again. Existing recordings were kept.'**
  String get backupErrorStartup;

  /// No description provided for @backupErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'The task could not be completed. Try again. If it keeps failing, keep a note of the steps for troubleshooting. Existing recordings were kept.'**
  String get backupErrorUnknown;

  /// No description provided for @backupRenamedTitle.
  ///
  /// In en, this message translates to:
  /// **'Folder names changed for import'**
  String get backupRenamedTitle;

  /// No description provided for @backupCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Backup created: {date}'**
  String backupCreatedAt(String date);

  /// No description provided for @backupByteProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total}'**
  String backupByteProgress(String done, String total);

  /// No description provided for @backupRecordingsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 recordings} =1{1 recording} other{{count} recordings}}'**
  String backupRecordingsCount(int count);

  /// No description provided for @backupFoldersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 folders} =1{1 folder} other{{count} folders}}'**
  String backupFoldersCount(int count);

  /// No description provided for @backupAddedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 recordings to add} =1{1 recording to add} other{{count} recordings to add}}'**
  String backupAddedCount(int count);

  /// No description provided for @backupDuplicateCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 duplicates skipped} =1{1 duplicate skipped} other{{count} duplicates skipped}}'**
  String backupDuplicateCount(int count);

  /// No description provided for @backupConflictCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 conflicting recordings skipped} =1{1 conflicting recording skipped} other{{count} conflicting recordings skipped}}'**
  String backupConflictCount(int count);

  /// No description provided for @backupAddedResult.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 recordings added} =1{1 recording added} other{{count} recordings added}}'**
  String backupAddedResult(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
