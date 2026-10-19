import 'l10n/localization.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'backup/library_coordinator.dart';
import 'backup/backup_document_service.dart';
import 'backup/backup_import_service.dart';
import 'backup/backup_controller.dart';
import 'backup/backup_page.dart';
import 'playback/audio_playback_service.dart';
import 'playback/playback_progress.dart';
import 'playback/recording_detail_page.dart';
import 'recording/recording_format.dart';
import 'recording/recording_service.dart';
import 'recording/recording_save_coordinator.dart';
import 'sharing/audio_share_service.dart';
import 'settings/recording_settings_page.dart';
import 'settings/app_language.dart';
import 'storage/app_storage_paths.dart';
import 'storage/folder_id.dart';
import 'storage/models/recording.dart';
import 'storage/models/recording_folder.dart';
import 'storage/recently_deleted_page.dart';
import 'storage/recording_store.dart';
import 'widgets/destructive_confirmation_dialog.dart';

Recording _copyRecording(
  Recording source, {
  String? title,
  String? folderId,
  bool updateFolderId = false,
}) => Recording(
  id: source.id,
  title: title ?? source.title,
  filePath: source.filePath,
  createdAt: source.createdAt,
  duration: source.duration,
  fileSizeBytes: source.fileSizeBytes,
  format: source.format,
  folderId: updateFolderId ? folderId : source.folderId,
  deletedAt: source.deletedAt,
  wasInterrupted: source.wasInterrupted,
);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.recordingService,
    this.recordingStore,
    this.playbackService,
    this.audioShareService,
  });

  final RecordingService? recordingService;
  final RecordingStore? recordingStore;
  final AudioPlaybackService? playbackService;
  final AudioShareService? audioShareService;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppLanguage _language = AppLanguage.simplifiedChinese;
  ThemeMode _themeMode = ThemeMode.system;
  late final RecordingService _recordingService =
      widget.recordingService ?? RecordingService();

  void _setThemeMode(ThemeMode mode) {
    if (mounted) setState(() => _themeMode = mode);
  }

  void _setLanguage(AppLanguage language) {
    if (mounted) setState(() => _language = language);
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff0b6657),
        brightness: brightness,
      ),
      scaffoldBackgroundColor: dark
          ? const Color(0xff101815)
          : const Color(0xfff2f7f4),
      appBarTheme: AppBarTheme(
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: brightness,
          systemNavigationBarColor: dark
              ? const Color(0xff101815)
              : const Color(0xfff2f7f4),
          systemNavigationBarIconBrightness: dark
              ? Brightness.light
              : Brightness.dark,
        ),
      ),
      useMaterial3: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => l10n(context).appTitle,
      locale: _language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _themeMode,
      home: RecordingHomePage(
        recordingService: _recordingService,
        recordingStore: widget.recordingStore,
        playbackService: widget.playbackService,
        audioShareService: widget.audioShareService,
        onThemeChanged: _setThemeMode,
        onLanguageChanged: _setLanguage,
      ),
    );
  }
}

class RecordingHomePage extends StatefulWidget {
  const RecordingHomePage({
    super.key,
    required this.recordingService,
    this.onThemeChanged,
    this.onLanguageChanged,
    this.recordingStore,
    this.playbackService,
    this.audioShareService,
  });

  final RecordingService recordingService;
  final ValueChanged<ThemeMode>? onThemeChanged;
  final ValueChanged<AppLanguage>? onLanguageChanged;
  final RecordingStore? recordingStore;
  final AudioPlaybackService? playbackService;
  final AudioShareService? audioShareService;

  @override
  State<RecordingHomePage> createState() => _RecordingHomePageState();
}

class _RecordingHomePageState extends State<RecordingHomePage>
    with WidgetsBindingObserver {
  static const _idleStatus = RecordingSessionStatus(
    state: RecordingLifecycleState.idle,
    elapsed: Duration.zero,
    canResume: false,
  );

  late final StreamSubscription<RecordingEvent> _eventSubscription;
  late final AudioPlaybackService _playbackService;
  late final StreamSubscription<PlaybackStatus> _playbackSubscription;
  late final bool _ownsPlaybackService;
  late final AudioShareService _audioShareService;
  RecordingSessionStatus _status = _idleStatus;
  PlaybackStatus _playbackStatus = const PlaybackStatus.idle();
  bool _isSubmitting = false;
  bool _isDetailOpen = false;
  bool _isPersistingRecording = false;
  int _pendingRecordingCommits = 0;
  bool _isRecoveringRecordings = false;
  late final RecordingSaveCoordinator _recordingSaveCoordinator;
  bool _isCancellingRecording = false;
  final _recordingPromptStatus = ValueNotifier(_idleStatus);
  DialogRoute<String>? _recordingPromptRoute;
  bool _isLoadingRecordings = true;
  bool _isSearching = false;
  bool _isSelecting = false;
  bool _isApplyingBatch = false;
  final Set<String> _selectedRecordingIds = {};
  String? _permissionMessage;
  String? _serviceError;
  String? _successMessage;
  String? _savedRecordingId;
  Timer? _successMessageTimer;
  String? _libraryError;
  String? _playbackError;
  List<Recording> _recordings = [];
  String _searchQuery = '';
  String? _selectedFolderId;
  String? _selectedFolderName;
  final GlobalKey _folderScopeButtonKey = GlobalKey();
  Future<RecordingStore>? _openedRecordingStore;
  LibraryCoordinator? _libraryCoordinator;
  bool _libraryProtected = false;
  BackupController? _backupController;
  bool _backupRouteOpen = false;
  bool _backupStartupFailed = false;
  bool _languageChangedInSettings = false;
  AppLocalizations _titleStrings = lookupAppLocalizations(
    AppLanguage.simplifiedChinese.locale,
  );

  List<Recording> get _visibleRecordings {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _recordings;
    }
    return _recordings
        .where((recording) => recording.title.toLowerCase().contains(query))
        .toList();
  }

  void _setSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
      _selectedRecordingIds.clear();
    });
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _selectedRecordingIds.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsPlaybackService = widget.playbackService == null;
    _playbackService = widget.playbackService ?? AudioPlaybackService();
    _audioShareService = widget.audioShareService ?? AudioShareService();
    _playbackStatus = _playbackService.status;
    _recordingSaveCoordinator = RecordingSaveCoordinator(
      service: widget.recordingService,
      getStore: _getRecordingStore,
      titleFor: _defaultTitle,
    );
    _playbackSubscription = _playbackService.statuses.listen(
      _handlePlaybackStatus,
    );
    _eventSubscription = widget.recordingService.events.listen(
      _handleRecordingEvent,
      onError: _handleEventError,
    );
    _loadCurrentStatus();
    _initializeLibrary();
    unawaited(_loadTheme());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _titleStrings = l10n(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _libraryCoordinator?.removeListener(_libraryProtectionChanged);
    _backupController?.removeListener(_backupUiChanged);
    _backupController?.dispose();
    _successMessageTimer?.cancel();
    _eventSubscription.cancel();
    _recordingPromptStatus.dispose();
    _playbackSubscription.cancel();
    if (_ownsPlaybackService) {
      unawaited(_playbackService.dispose());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cleanupExpiredRecordings();
      unawaited(_recoverRecordings());
    }
  }

  Future<void> _loadTheme() async {
    if (widget.onThemeChanged == null) return;
    try {
      final mode = await (await _getRecordingStore()).getThemeMode();
      if (mounted) widget.onThemeChanged?.call(mode);
    } catch (_) {
      // Settings offers a retry; keep the system theme while storage is unavailable.
    }
  }

  Future<void> _loadLanguage() async {
    if (widget.onLanguageChanged == null) return;
    try {
      final language = await (await _getRecordingStore()).getAppLanguage();
      if (!mounted || _languageChangedInSettings) return;
      _titleStrings = lookupAppLocalizations(language.locale);
      widget.onLanguageChanged?.call(language);
      await widget.recordingService.setAppLanguage(language.code);
    } catch (_) {
      // Settings offers a retry if preferences or native synchronization fail.
    }
  }

  void _languageChanged(AppLanguage language) {
    _languageChangedInSettings = true;
    _titleStrings = lookupAppLocalizations(language.locale);
    widget.onLanguageChanged?.call(language);
  }

  Future<void> _initializeLibrary() async {
    await _loadLanguage();
    await _recoverRecordings();
    await _loadRecordings();
    await _cleanupExpiredRecordings();
  }

  Future<void> _recoverRecordings() async {
    if (_isRecoveringRecordings) return;
    _isRecoveringRecordings = true;
    try {
      final store = await _getRecordingStore();
      await store.coordinator.deferMutation(() async {
        final batch = await widget.recordingService.recoverRecordings();
        var indexFailures = 0;
        for (final ready in batch.recordings) {
          if (!await _persistSavedRecording(ready)) indexFailures++;
        }
        if (indexFailures > 0) {
          _setServiceError('recoveryIndexFailed');
        } else if (batch.unresolvedCount > 0) {
          _setServiceError('recoveryUnresolved');
        }
      });
    } catch (_) {
      _setServiceError('recoveryCheckFailed');
    } finally {
      _isRecoveringRecordings = false;
    }
  }

  Future<void> _cleanupExpiredRecordings() async {
    try {
      final failures = await (await _getRecordingStore())
          .purgeExpiredRecordings();
      if (failures.isNotEmpty) {
        _setServiceError('expiredCleanupPartial');
      }
    } catch (_) {
      _setServiceError('expiredCleanupFailed');
    }
  }

  Future<void> _openRecentlyDeleted() async {
    try {
      final store = await _getRecordingStore();
      if (!mounted) return;
      await _playbackService.stop();
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => RecentlyDeletedPage(store: store)),
      );
      if (mounted) await _loadRecordings();
    } catch (_) {
      _setLibraryError('openDeletedFailed');
    }
  }

  Future<void> _openRecordingSettings() async {
    try {
      final store = await _getRecordingStore(allowRecoveryFailure: true);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RecordingSettingsPage(
            store: store,
            service: widget.recordingService,
            onThemeChanged: widget.onThemeChanged,
            onLanguageChanged: _languageChanged,
            backupController: _backupController,
            onOpenBackup: _openBackup,
          ),
        ),
      );
    } catch (_) {
      _setServiceError('openSettingsFailed');
    }
  }

  Future<void> _openBackup() async {
    if (!mounted || _backupRouteOpen || _backupController == null) return;
    _backupRouteOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => BackupPage(controller: _backupController!),
        ),
      );
    } finally {
      _backupRouteOpen = false;
    }
  }

  // Called inside setState so replacement and clearing render together with
  // the recording state. Only one success message and timer may exist.
  void _updateSuccessMessage(String? message, {String? recordingId}) {
    _successMessageTimer?.cancel();
    _successMessageTimer = null;
    _successMessage = message;
    _savedRecordingId = recordingId;
    if (message != null) {
      _successMessageTimer = Timer(
        const Duration(seconds: 4),
        _dismissSuccessMessage,
      );
    }
  }

  void _dismissSuccessMessage() {
    if (!mounted) return;
    setState(() => _updateSuccessMessage(null));
  }

  Future<void> _renameSavedRecording() async {
    final id = _savedRecordingId;
    if (id == null || _isSubmitting || _libraryProtected) return;
    _dismissSuccessMessage();
    try {
      final recordings = await (await _getRecordingStore()).listRecordings();
      if (!mounted || _libraryProtected) return;
      final matches = recordings.where((recording) => recording.id == id);
      if (matches.isNotEmpty) await _renameRecording(matches.first);
    } catch (_) {
      _setServiceError('renameRecordingFailed');
    }
  }

  Future<void> _loadCurrentStatus() async {
    try {
      final status = await widget.recordingService.getStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
      });
    } on PlatformException catch (error) {
      _setServiceError(
        nativeMessageCode(error.code, fallback: 'statusReadFailed'),
      );
    } on FormatException {
      _setServiceError('statusReadFailed');
    }
  }

  Future<void> _loadRecordings() async {
    final folderId = _selectedFolderId;
    try {
      final store = await _getRecordingStore();
      final recordings = await store.listRecordings(folderId: folderId);
      if (!mounted || folderId != _selectedFolderId) {
        return;
      }
      setState(() {
        _recordings = recordings;
        _selectedRecordingIds.retainAll(_visibleRecordings.map((r) => r.id));
        _isLoadingRecordings = false;
        _libraryError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingRecordings = false;
        _libraryError = 'libraryReadFailed';
      });
    }
  }

  Future<void> _openFolderScopeMenu() async {
    if (_isSubmitting || _isSearching || _isSelecting) return;
    try {
      final store = await _getRecordingStore();
      final folders = await store.listFolders();
      if (!mounted) return;
      final buttonBox =
          _folderScopeButtonKey.currentContext?.findRenderObject()
              as RenderBox?;
      final overlay =
          Navigator.of(context).overlay?.context.findRenderObject()
              as RenderBox?;
      if (buttonBox == null || overlay == null) return;
      final position = RelativeRect.fromRect(
        Rect.fromPoints(
          buttonBox.localToGlobal(Offset.zero, ancestor: overlay),
          buttonBox.localToGlobal(
            buttonBox.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      );
      final selected = await showMenu<String>(
        context: context,
        position: position,
        initialValue: _selectedFolderId ?? '',
        semanticLabel: l10n(context).selectScope,
        elevation: 8,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          maxWidth: MediaQuery.sizeOf(context).width - 24,
        ),
        items: [
          _folderScopeMenuItem(
            id: '',
            title: l10n(context).allRecordings,
            icon: Icons.library_music_outlined,
          ),
          for (final folder in folders)
            _folderScopeMenuItem(
              id: folder.id,
              title: folder.name,
              icon: Icons.folder_outlined,
            ),
        ],
      );
      if (!mounted || selected == null) return;
      await _selectFolderScope(store, selected.isEmpty ? null : selected);
    } catch (_) {
      _setLibraryError('foldersReadFailed');
    }
  }

  PopupMenuItem<String> _folderScopeMenuItem({
    required String id,
    required String title,
    required IconData icon,
  }) {
    final selected = (_selectedFolderId ?? '') == id;
    final colors = Theme.of(context).colorScheme;
    return PopupMenuItem<String>(
      value: id,
      height: 52,
      child: Row(
        children: [
          Icon(icon, color: selected ? colors.primary : null),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_rounded, color: colors.primary, size: 20),
          ],
        ],
      ),
    );
  }

  Future<void> _selectFolderScope(
    RecordingStore store,
    String? folderId,
  ) async {
    if (_isSubmitting) return;
    if (folderId == _selectedFolderId) {
      return;
    }
    try {
      final folders = await store.listFolders();
      if (!mounted) return;
      final selectedFolder = folders.where((folder) => folder.id == folderId);
      setState(() {
        _selectedFolderId = folderId;
        _selectedRecordingIds.clear();
        _selectedFolderName = selectedFolder.isEmpty
            ? null
            : selectedFolder.single.name;
        _isLoadingRecordings = true;
        _libraryError = null;
      });
      await _loadRecordings();
    } catch (_) {
      _setLibraryError('foldersReadFailed');
    }
  }

  void _setLibraryError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoadingRecordings = false;
      _libraryError = message;
    });
  }

  Future<void> _togglePlayback(Recording recording) async {
    setState(() {
      _playbackError = null;
    });
    await _playbackService.toggle(recording);
  }

  Future<void> _openRecordingDetail(Recording recording) async {
    if (_isSelecting || _isSubmitting || _isDetailOpen) return;
    _isDetailOpen = true;
    setState(() => _playbackError = null);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RecordingDetailPage(
            recording: recording,
            playbackService: _playbackService,
            onRename: (value, onUpdated) => _renameRecording(value, onUpdated),
            onMove: (value, onUpdated) => _moveRecording(value, onUpdated),
            onShare: _shareRecording,
            canModify: !_libraryProtected,
          ),
        ),
      );
    } finally {
      _isDetailOpen = false;
    }
  }

  Future<void> _shareRecording(Recording recording) async {
    setState(() {
      _isSubmitting = true;
      _serviceError = null;
    });
    try {
      await _audioShareService.shareRecording(
        recording,
        fallbackTitle: l10n(context).recordingBaseName,
      );
    } catch (_) {
      _setServiceError('shareFailed');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _renameRecording(
    Recording recording, [
    ValueChanged<Recording>? onUpdated,
  ]) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) =>
          _RenameRecordingDialog(initialTitle: recording.title),
    );

    final normalizedTitle = title?.trim();
    if (normalizedTitle == null || normalizedTitle.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serviceError = null;
    });
    try {
      final store = await _getRecordingStore();
      await store.renameRecording(
        recordingId: recording.id,
        title: normalizedTitle,
      );
      onUpdated?.call(_copyRecording(recording, title: normalizedTitle));
      await _loadRecordings();
    } catch (_) {
      _setServiceError('renameRecordingFailed');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _moveRecording(
    Recording recording, [
    ValueChanged<Recording>? onUpdated,
  ]) async {
    try {
      final folders = await (await _getRecordingStore()).listFolders();
      if (!mounted) {
        return;
      }
      final destinations = folders
          .where((folder) => folder.id != recording.folderId)
          .toList();
      if (recording.folderId == null && destinations.isEmpty) {
        _setServiceError('createFolderFirst');
        return;
      }

      final selectedFolderId = await showModalBottomSheet<String?>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text(l10n(context).moveRecordingTo)),
              if (recording.folderId != null)
                ListTile(
                  key: Key('moveRecording-${recording.id}-all'),
                  leading: const Icon(Icons.library_music_outlined),
                  title: Text(l10n(context).allRecordings),
                  onTap: () => Navigator.pop(context, ''),
                ),
              for (final folder in destinations)
                ListTile(
                  key: Key('moveRecording-${recording.id}-${folder.id}'),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name),
                  onTap: () => Navigator.pop(context, folder.id),
                ),
            ],
          ),
        ),
      );
      if (!mounted || selectedFolderId == null) {
        return;
      }

      setState(() {
        _isSubmitting = true;
        _serviceError = null;
      });
      final store = await _getRecordingStore();
      await store.moveRecording(
        recordingId: recording.id,
        folderId: selectedFolderId.isEmpty ? null : selectedFolderId,
      );
      onUpdated?.call(
        _copyRecording(
          recording,
          folderId: selectedFolderId.isEmpty ? null : selectedFolderId,
          updateFolderId: true,
        ),
      );
      await _loadRecordings();
    } catch (_) {
      _setServiceError('moveRecordingFailed');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _deleteRecording(Recording recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DestructiveConfirmationDialog(
        title: l10n(context).deleteRecordingTitle,
        message: l10n(context).deleteRecordingDescription,
        actionLabel: l10n(context).moveToDeleted,
        onConfirm: () => Navigator.pop(context, true),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serviceError = null;
    });
    try {
      if (_playbackStatus.recordingId == recording.id) {
        await _playbackService.stop();
      }
      final store = await _getRecordingStore();
      await store.softDeleteRecording(
        recordingId: recording.id,
        deletedAt: DateTime.now(),
      );
      await _loadRecordings();
    } catch (_) {
      _setServiceError('deleteRecordingFailed');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _exitSelection() {
    if (_isSubmitting) return;
    setState(() {
      _isSelecting = false;
      _selectedRecordingIds.clear();
    });
  }

  void _toggleSelection(String id) {
    if (_isSubmitting) return;
    setState(() {
      _isSelecting = true;
      if (!_selectedRecordingIds.add(id)) {
        _selectedRecordingIds.remove(id);
      }
    });
  }

  Future<void> _operateOnSelection({required bool delete}) async {
    if (_isSubmitting || _selectedRecordingIds.isEmpty) return;
    final ids = _selectedRecordingIds.toSet();
    // Lock selection and navigation while choosing a destination or confirming.
    setState(() {
      _isSubmitting = true;
      _serviceError = null;
    });
    try {
      final store = await _getRecordingStore();
      if (!mounted) return;
      if (delete) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => DestructiveConfirmationDialog(
            title: l10n(context).deleteSelectedTitle(ids.length),
            message: l10n(context).deleteRecordingDescription,
            actionLabel: l10n(context).moveToDeleted,
            onConfirm: () => Navigator.pop(context, true),
          ),
        );
        if (confirmed != true || !mounted) return;
        setState(() => _isApplyingBatch = true);
        if (ids.contains(_playbackStatus.recordingId)) {
          await _playbackService.stop();
        }
        await store.softDeleteRecordings(
          recordingIds: ids,
          deletedAt: DateTime.now(),
        );
      } else {
        final folders = await store.listFolders();
        if (!mounted) return;
        final selected = _recordings.where((r) => ids.contains(r.id)).toList();
        final destinations = folders
            .where((f) => selected.any((r) => r.folderId != f.id))
            .toList();
        final canMoveToAll = selected.any((r) => r.folderId != null);
        if (!canMoveToAll && destinations.isEmpty) {
          _setServiceError('createFolderFirst');
          return;
        }
        final destination = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(l10n(context).moveSelectedTitle(ids.length)),
                  ),
                  if (canMoveToAll)
                    ListTile(
                      key: const Key('batchMove-all'),
                      title: Text(l10n(context).allRecordings),
                      onTap: () => Navigator.pop(context, ''),
                    ),
                  for (final folder in destinations)
                    ListTile(
                      key: Key('batchMove-${folder.id}'),
                      title: Text(folder.name),
                      onTap: () => Navigator.pop(context, folder.id),
                    ),
                ],
              ),
            ),
          ),
        );
        if (destination == null || !mounted) return;
        setState(() => _isApplyingBatch = true);
        await store.moveRecordings(
          recordingIds: ids,
          folderId: destination.isEmpty ? null : destination,
        );
      }
      if (!mounted) return;
      setState(() {
        _isSelecting = false;
        _selectedRecordingIds.clear();
      });
      await _loadRecordings();
    } catch (_) {
      _setServiceError(delete ? 'batchDeleteFailed' : 'batchMoveFailed');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isApplyingBatch = false;
        });
      }
    }
  }

  Future<void> _openFolderManagement() async {
    final store = await _getRecordingStore();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _FolderManagementPage(
          coordinator: store.coordinator,
          listFolders: () async => (await _getRecordingStore()).listFolders(),
          reorderFolders: (ids) async =>
              (await _getRecordingStore()).reorderFolders(ids),
          listRecordings: (folderId) async =>
              (await _getRecordingStore()).listRecordings(folderId: folderId),
          createFolder: (name) async {
            final store = await _getRecordingStore();
            return store.createFolder(id: newFolderId(), name: name);
          },
          renameFolder: (folderId, name) async {
            await (await _getRecordingStore()).renameFolder(
              folderId: folderId,
              name: name,
            );
          },
          deleteFolder: (folderId, action) async {
            await (await _getRecordingStore()).deleteFolder(
              folderId: folderId,
              action: action,
            );
          },
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    try {
      final folders = await (await _getRecordingStore()).listFolders();
      if (!mounted) {
        return;
      }
      if (_selectedFolderId != null &&
          !folders.any((folder) => folder.id == _selectedFolderId)) {
        setState(() {
          _selectedFolderId = null;
          _selectedFolderName = null;
        });
      }
      await _loadRecordings();
    } catch (_) {
      _setLibraryError('foldersRefreshFailed');
    }
  }

  void _handlePlaybackStatus(PlaybackStatus status) {
    if (!mounted) {
      return;
    }
    setState(() {
      _playbackStatus = status;
      _playbackError = status.errorMessage;
    });
  }

  Future<void> _requestPermissionAndStart() async {
    if (_isSubmitting || !_canStart) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _permissionMessage = null;
      _serviceError = null;
      _updateSuccessMessage(null);
    });

    try {
      final store = await _getRecordingStore();
      await store.coordinator.mutate(() async {
        await _playbackService.stop();
        final granted = await widget.recordingService
            .requestMicrophonePermission();
        if (!mounted) {
          return;
        }
        if (!granted) {
          setState(() {
            _permissionMessage = 'microphoneRequired';
          });
          return;
        }

        final RecordingFormat format;
        try {
          format = await (await _getRecordingStore())
              .getDefaultRecordingFormat();
        } catch (_) {
          _setServiceError('defaultFormatReadFailed');
          return;
        }
        if (!mounted) return;
        setState(() {
          _status = RecordingSessionStatus(
            state: RecordingLifecycleState.preparing,
            format: format,
            elapsed: Duration.zero,
            canResume: false,
          );
        });
        await widget.recordingService.start(format: format);
      });
    } on PlatformException catch (error) {
      final unavailableMessage = _status.format == RecordingFormat.aac
          ? 'aacUnavailable'
          : 'mp3Unavailable';
      if (mounted &&
          _status.state == RecordingLifecycleState.preparing &&
          _status.sessionId == null) {
        setState(() => _status = _idleStatus);
      }
      _setServiceError(
        error.code == 'recording-format-unavailable'
            ? unavailableMessage
            : nativeMessageCode(error.code, fallback: 'startFailed'),
      );
    } catch (_) {
      if (mounted &&
          _status.state == RecordingLifecycleState.preparing &&
          _status.sessionId == null) {
        setState(() => _status = _idleStatus);
      }
      _setServiceError('startRetryFailed');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _openAppSettings() async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serviceError = null;
    });
    try {
      await widget.recordingService.openAppSettings();
    } on PlatformException catch (error) {
      _setServiceError(
        nativeMessageCode(error.code, fallback: 'systemSettingsFailed'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _pauseOrResume() async {
    if (_isSubmitting || (!_canPause && !_canResume)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serviceError = null;
    });
    try {
      if (_canPause) {
        await widget.recordingService.pause();
      } else {
        await widget.recordingService.resume();
      }
    } on PlatformException catch (error) {
      _setServiceError(
        nativeMessageCode(error.code, fallback: 'recordingUpdateFailed'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _stopAndSave() async {
    if (_isSubmitting || !_canStop) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serviceError = null;
      _status = RecordingSessionStatus(
        state: RecordingLifecycleState.stopping,
        elapsed: _status.elapsed,
        canResume: false,
        sessionId: _status.sessionId,
        format: _status.format,
      );
    });
    try {
      await widget.recordingService.stop();
    } on PlatformException catch (error) {
      _setServiceError(
        nativeMessageCode(error.code, fallback: 'recordingStopFailed'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _confirmCancellation() async {
    if (_isSubmitting || !_canCancel || _recordingPromptRoute != null) return;
    final sessionId = _status.sessionId;
    final shouldCancel = await _showRecordingPrompt((context, status) {
      return DestructiveConfirmationDialog(
        title: l10n(context).discardTitle,
        message: l10n(
          context,
        ).discardRecordingDuration(_formatDuration(status.elapsed)),
        actionLabel: l10n(context).discardRecording,
        onConfirm: () => Navigator.pop(context, 'discard'),
      );
    });
    if (shouldCancel != 'discard' ||
        !mounted ||
        _isSubmitting ||
        !_canCancel ||
        _status.sessionId != sessionId) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _isCancellingRecording = true;
      _serviceError = null;
      _updateSuccessMessage(null);
    });
    try {
      await widget.recordingService.cancel();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _isCancellingRecording = false;
          _serviceError = nativeMessageCode(
            error.code,
            fallback: 'discardFailed',
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<String?> _showRecordingPrompt(
    Widget Function(BuildContext, RecordingSessionStatus) builder,
  ) async {
    _recordingPromptStatus.value = _status;
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => ValueListenableBuilder<RecordingSessionStatus>(
        valueListenable: _recordingPromptStatus,
        builder: (context, status, _) => builder(context, status),
      ),
    );
    _recordingPromptRoute = route;
    try {
      return await Navigator.of(context).push(route);
    } finally {
      if (identical(_recordingPromptRoute, route)) {
        _recordingPromptRoute = null;
      }
    }
  }

  void _closeRecordingPrompt() {
    final route = _recordingPromptRoute;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  Future<void> _confirmRecordingExit() async {
    if (_isSubmitting || !_canStop || _recordingPromptRoute != null) return;
    final sessionId = _status.sessionId;
    final action = await _showRecordingPrompt((context, status) {
      final strings = l10n(context);
      final paused = status.state == RecordingLifecycleState.paused;
      return AlertDialog(
        key: const Key('recordingExitDialog'),
        scrollable: true,
        title: Text(strings.endRecordingTitle),
        content: Text(
          paused ? strings.endRecordingPaused : strings.endRecordingActive,
        ),
        actions: [
          TextButton(
            key: const Key('keepRecording'),
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: Text(
              paused ? strings.keepPaused : strings.continueRecording,
            ),
          ),
          DestructiveActionButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            filled: false,
            label: strings.discardRecording,
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: Text(strings.saveAndEndRecording),
          ),
        ],
      );
    });
    if (!mounted ||
        _isSubmitting ||
        !_canStop ||
        _status.sessionId != sessionId) {
      return;
    }
    if (action == 'save') await _stopAndSave();
    if (action == 'discard') await _confirmCancellation();
  }

  void _handleRecordingEvent(RecordingEvent event) {
    if (!mounted) {
      return;
    }

    switch (event) {
      case RecordingStateChanged(:final status):
        final previousSessionId = _status.sessionId;
        setState(() {
          final cancellationCompleted =
              _isCancellingRecording &&
              status.state == RecordingLifecycleState.idle;
          _status = status;
          if (status.state == RecordingLifecycleState.failed ||
              previousSessionId != status.sessionId) {
            _isCancellingRecording = false;
          }
          if (status.state == RecordingLifecycleState.preparing) {
            _serviceError = null;
          }
          if (cancellationCompleted) {
            _isCancellingRecording = false;
            _updateSuccessMessage('recordingDiscarded');
          }
        });
        _recordingPromptStatus.value = status;
        // An interruption or a different session invalidates both confirmations.
        if (!_canCancel || previousSessionId != status.sessionId) {
          _closeRecordingPrompt();
        }
      case RecordingFileReady(:final recording):
        _closeRecordingPrompt();
        unawaited(_persistSavedRecording(recording));
      case RecordingFailed(:final code):
        _closeRecordingPrompt();
        setState(() {
          _isCancellingRecording = false;
          _serviceError = nativeMessageCode(code);
        });
    }
  }

  void _handleEventError(Object error, StackTrace stackTrace) {
    _setServiceError('serviceConnectionFailed');
  }

  void _setServiceError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _serviceError = message;
    });
    if (_isDetailOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedMessage(context, message))),
      );
    }
  }

  Future<bool> _persistSavedRecording(
    SavedNativeRecording savedRecording,
  ) async {
    if (mounted) {
      setState(() {
        _pendingRecordingCommits++;
        _isPersistingRecording = true;
        _updateSuccessMessage(null);
        _serviceError = null;
      });
    }

    try {
      final result = await _recordingSaveCoordinator.commit(savedRecording);
      if (!mounted) {
        return true;
      }
      setState(() {
        if (_status.sessionId == null ||
            _status.sessionId == savedRecording.id) {
          _status = _idleStatus;
        }
        if (result.acknowledgementPending) {
          _serviceError = 'savedCleanupPending';
        } else if (result.inserted && savedRecording.wasInterrupted) {
          _serviceError = 'interruptedSaved';
        } else if (result.inserted) {
          _updateSuccessMessage(
            'recordingSaved',
            recordingId: savedRecording.id,
          );
        }
      });
      await _loadRecordings();
      return true;
    } catch (_) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _serviceError = 'saveIndexFailed';
      });
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _pendingRecordingCommits--;
          _isPersistingRecording = _pendingRecordingCommits > 0;
        });
      }
    }
  }

  void _backupUiChanged() {
    if (!mounted) return;
    final failed = _backupController?.startupFailure ?? false;
    if (failed != _backupStartupFailed) {
      setState(() => _backupStartupFailed = failed);
      if (!failed) unawaited(_loadRecordings());
    }
  }

  Future<RecordingStore> _getRecordingStore({
    bool allowRecoveryFailure = false,
  }) async {
    final store =
        widget.recordingStore ??
        await (_openedRecordingStore ??= _openDefaultRecordingStore());
    widget.recordingService.bindLibraryCoordinator(store.coordinator);
    if (mounted && !identical(_libraryCoordinator, store.coordinator)) {
      _libraryCoordinator?.removeListener(_libraryProtectionChanged);
      _libraryCoordinator = store.coordinator;
      _libraryProtected = store.coordinator.isProtected;
      store.coordinator.addListener(_libraryProtectionChanged);
    }
    var newController = false;
    if (mounted && _backupController == null) {
      _backupController =
          BackupController(
              store: store,
              recordingService: widget.recordingService,
            )
            ..onOpenRequested = () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) unawaited(_openBackup());
              });
              WidgetsBinding.instance.ensureVisualUpdate();
            };
      newController = true;
      _backupController!.addListener(_backupUiChanged);
    }
    try {
      await store.coordinator.ensureInitialized();
    } catch (error) {
      _backupController?.showStartupFailure(error);
      if (!allowRecoveryFailure) rethrow;
      return store;
    }
    if (newController || (_backupController?.startupFailure ?? false)) {
      unawaited(_backupController!.initialize());
    }
    return store;
  }

  void _libraryProtectionChanged() {
    if (!mounted) return;
    final protected = _libraryCoordinator!.isProtected;
    if (_libraryProtected == protected) return;
    setState(() {
      _libraryProtected = protected;
      if (protected) {
        _isSelecting = false;
        _selectedRecordingIds.clear();
      }
    });
    if (!protected) unawaited(_loadRecordings());
  }

  static Future<RecordingStore> _openDefaultRecordingStore() async {
    final paths = await AppStoragePaths.create();
    late final RecordingStore store;
    store = RecordingStore(
      databasePath: paths.databasePath,
      libraryCoordinator: LibraryCoordinator(
        recoverInterruptedTask: () async {
          await BackupDocumentService().recoverInterruptedTransfer();
          await BackupImportRecovery(
            paths,
            store,
            onRecovered: (taskId, committed) {
              store.coordinator.recoveredImportTaskId = taskId;
              store.coordinator.recoveredImportCommitted = committed;
            },
          ).recover();
        },
      ),
    );
    await store.open();
    return store;
  }

  String _defaultTitle(DateTime createdAt) {
    final localTime = createdAt.toLocal();
    final month = localTime.month.toString().padLeft(2, '0');
    final day = localTime.day.toString().padLeft(2, '0');
    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');
    return _titleStrings.defaultRecordingTitle(
      '${localTime.year}-$month-$day $hour:$minute',
    );
  }

  bool get _canStart =>
      !_libraryProtected &&
      !_backupStartupFailed &&
      !_isPersistingRecording &&
      (_status.state == RecordingLifecycleState.idle ||
          _status.state == RecordingLifecycleState.failed);

  bool get _hasActiveSession => switch (_status.state) {
    RecordingLifecycleState.preparing ||
    RecordingLifecycleState.recording ||
    RecordingLifecycleState.paused ||
    RecordingLifecycleState.discarding ||
    RecordingLifecycleState.stopping => true,
    RecordingLifecycleState.idle || RecordingLifecycleState.failed => false,
  };

  bool get _canPause =>
      !_isCancellingRecording &&
      _status.state == RecordingLifecycleState.recording;

  bool get _canResume =>
      !_isCancellingRecording &&
      _status.state == RecordingLifecycleState.paused &&
      _status.canResume;

  bool get _canStop =>
      !_isCancellingRecording &&
      (_status.state == RecordingLifecycleState.recording ||
          _status.state == RecordingLifecycleState.paused);

  bool get _canCancel =>
      !_isCancellingRecording &&
      switch (_status.state) {
        RecordingLifecycleState.preparing ||
        RecordingLifecycleState.recording ||
        RecordingLifecycleState.paused => true,
        RecordingLifecycleState.idle ||
        RecordingLifecycleState.stopping ||
        RecordingLifecycleState.discarding ||
        RecordingLifecycleState.failed => false,
      };

  @override
  Widget build(BuildContext context) {
    if (!_hasActiveSession && _status.state != RecordingLifecycleState.failed) {
      return _buildRecordingLibrary(context);
    }

    return PopScope(
      canPop: !_hasActiveSession && !_isSubmitting && !_isPersistingRecording,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_confirmRecordingExit());
      },
      child: _buildRecordingControls(context),
    );
  }

  Widget _buildRecordingLibrary(BuildContext context) {
    return PopScope(
      canPop: !_isSelecting && !_isSubmitting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelecting) _exitSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isSearching
              ? TextField(
                  key: const Key('recordingSearchField'),
                  autofocus: true,
                  enabled: !_isSubmitting,
                  onChanged: _setSearchQuery,
                  decoration: InputDecoration(
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    hintText: _selectedFolderName == null
                        ? l10n(context).searchAll
                        : l10n(context).searchFolder(_selectedFolderName!),
                    border: InputBorder.none,
                  ),
                )
              : Semantics(
                  label: l10n(context).switchScope(
                    _selectedFolderName ?? l10n(context).allRecordings,
                  ),
                  button: true,
                  enabled: !_isSubmitting,
                  onTap: _isSubmitting ? null : _openFolderScopeMenu,
                  child: ExcludeSemantics(
                    child: KeyedSubtree(
                      key: const Key('folderScopeSelector'),
                      child: TextButton(
                        key: _folderScopeButtonKey,
                        onPressed: _isSubmitting ? null : _openFolderScopeMenu,
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSurface,
                          minimumSize: const Size(48, 48),
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                          textStyle: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _selectedFolderName ??
                                    l10n(context).allRecordings,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          titleSpacing: 24,
          centerTitle: false,
          backgroundColor: Colors.transparent,
          actions: [
            if (_isSelecting)
              IconButton(
                tooltip: l10n(context).exitSelection,
                onPressed: _isSubmitting ? null : _exitSelection,
                icon: const Icon(Icons.close),
              ),
            if (!_isSelecting)
              IconButton(
                tooltip: l10n(context).selectRecordings,
                onPressed: _isSubmitting || _visibleRecordings.isEmpty
                    ? null
                    : () => setState(() {
                        _isSelecting = true;
                      }),
                icon: const Icon(Icons.checklist),
              ),
            IconButton(
              key: const Key('recordingSearchButton'),
              tooltip: _isSearching
                  ? l10n(context).closeSearch
                  : l10n(context).searchRecordings,
              onPressed: _isSubmitting
                  ? null
                  : () {
                      if (_isSearching) {
                        _closeSearch();
                      } else {
                        setState(() {
                          _isSearching = true;
                        });
                      }
                    },
              icon: Icon(
                _isSearching ? Icons.close_rounded : Icons.search_rounded,
              ),
            ),
            PopupMenuButton<String>(
              enabled: !_isSelecting && !_isSubmitting,
              key: const Key('manageFoldersMenu'),
              tooltip: l10n(context).more,
              onSelected: (action) {
                if (action == 'folders') {
                  _openFolderManagement();
                } else if (action == 'recentlyDeleted') {
                  _openRecentlyDeleted();
                } else if (action == 'settings') {
                  _openRecordingSettings();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  key: Key('manageFoldersItem'),
                  value: 'folders',
                  child: Text(l10n(context).manageFolders),
                ),
                PopupMenuItem(
                  value: 'recentlyDeleted',
                  child: Text(l10n(context).recentlyDeleted),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: Text(l10n(context).settings),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_permissionMessage != null ||
                  _libraryProtected ||
                  _backupStartupFailed ||
                  _serviceError != null ||
                  _successMessage != null ||
                  _playbackError != null)
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_libraryProtected)
                            BackupProtectionNotice(onOpen: _openBackup),
                          if (_backupStartupFailed) ...[
                            Text(l10n(context).backupErrorCleanup),
                            TextButton(
                              onPressed: _openBackup,
                              child: Text(l10n(context).backupLastResult),
                            ),
                          ],
                          if (_permissionMessage != null) ...[
                            _MessagePanel(
                              icon: Icons.mic_off_rounded,
                              message: _permissionMessage!,
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: _isSubmitting
                                    ? null
                                    : _openAppSettings,
                                icon: const Icon(Icons.settings_outlined),
                                label: Text(l10n(context).openSystemSettings),
                              ),
                            ),
                          ],
                          if (_serviceError != null)
                            _MessagePanel(
                              icon: Icons.error_outline_rounded,
                              message: _serviceError!,
                              isError: true,
                            ),
                          if (_successMessage != null)
                            _MessagePanel(
                              icon: Icons.check_circle_outline_rounded,
                              message: _successMessage!,
                              onDismiss: _dismissSuccessMessage,
                              onAction:
                                  _savedRecordingId != null &&
                                      !_libraryProtected &&
                                      !_isSubmitting
                                  ? _renameSavedRecording
                                  : null,
                            ),
                          if (_playbackError != null)
                            _MessagePanel(
                              icon: Icons.error_outline_rounded,
                              message: _playbackError!,
                              isError: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(child: _buildRecordingList(context)),
              if (_isSelecting)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n(
                                  context,
                                ).selectedCount(_selectedRecordingIds.length),
                              ),
                            ),
                            TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () => setState(() {
                                      final visibleIds = _visibleRecordings
                                          .map((r) => r.id)
                                          .toSet();
                                      if (visibleIds.isNotEmpty &&
                                          _selectedRecordingIds.containsAll(
                                            visibleIds,
                                          )) {
                                        _selectedRecordingIds.clear();
                                      } else {
                                        _selectedRecordingIds.addAll(
                                          visibleIds,
                                        );
                                      }
                                    }),
                              child: Text(
                                _visibleRecordings.isNotEmpty &&
                                        _selectedRecordingIds.length ==
                                            _visibleRecordings.length
                                    ? l10n(context).deselectAll
                                    : l10n(context).selectAll,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    _isSubmitting ||
                                        _selectedRecordingIds.isEmpty
                                    ? null
                                    : () => _operateOnSelection(delete: false),
                                icon: const Icon(Icons.drive_file_move_outline),
                                label: Text(l10n(context).move),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.error,
                                ),
                                onPressed:
                                    _isSubmitting ||
                                        _selectedRecordingIds.isEmpty
                                    ? null
                                    : () => _operateOnSelection(delete: true),
                                icon: const Icon(Icons.delete_outline),
                                label: Text(l10n(context).delete),
                              ),
                            ),
                          ],
                        ),
                        if (_isApplyingBatch) const LinearProgressIndicator(),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: _isSelecting
            ? null
            : _buildLibraryBottomBar(context),
      ),
    );
  }

  Widget _buildLibraryBottomBar(BuildContext context) {
    final player = _buildPlaybackControls(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?player,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: FloatingActionButton.extended(
                onPressed: _isSubmitting || !_canStart
                    ? null
                    : _requestPermissionAndStart,
                icon: const Icon(Icons.mic_rounded),
                label: Text(
                  _permissionMessage == null
                      ? l10n(context).startRecording
                      : l10n(context).requestAgain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingList(BuildContext context) {
    if (_isLoadingRecordings) {
      return Center(child: CircularProgressIndicator());
    }

    if (_libraryError != null) {
      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48),
                const SizedBox(height: 16),
                Text(localizedMessage(context, _libraryError!)),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _loadRecordings,
                  child: Text(l10n(context).reload),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_recordings.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mic_none_rounded,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n(context).noRecordings,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(l10n(context).noRecordingsDescription),
              ],
            ),
          ),
        ),
      );
    }

    final visibleRecordings = _visibleRecordings;
    if (visibleRecordings.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search_off_rounded, size: 56),
                const SizedBox(height: 16),
                Text(l10n(context).noMatches),
                const SizedBox(height: 8),
                Text(l10n(context).noMatchesDescription),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        if (!_isSubmitting) await _loadRecordings();
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        itemCount: visibleRecordings.length,
        separatorBuilder: (context, _) => Divider(
          height: 1,
          indent: 64,
          endIndent: 16,
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        itemBuilder: (context, index) {
          final recording = visibleRecordings[index];
          final isPlaying =
              _playbackStatus.recordingId == recording.id &&
              _playbackStatus.state == PlaybackState.playing;
          final isCurrent = _playbackStatus.recordingId == recording.id;
          final colors = Theme.of(context).colorScheme;
          return ListTile(
            key: Key('recordingRow-${recording.id}'),
            tileColor: isCurrent && !_isSelecting
                ? colors.primaryContainer.withValues(alpha: 0.35)
                : null,
            minLeadingWidth: 48,
            horizontalTitleGap: 8,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            selected: _selectedRecordingIds.contains(recording.id),
            onTap: _isSubmitting
                ? null
                : () => _isSelecting
                      ? _toggleSelection(recording.id)
                      : _openRecordingDetail(recording),
            onLongPress: _isSubmitting
                ? null
                : () => _toggleSelection(recording.id),
            leading: _isSelecting
                ? Checkbox(
                    value: _selectedRecordingIds.contains(recording.id),
                    semanticLabel: l10n(
                      context,
                    ).selectRecording(recording.title),
                    onChanged: _isSubmitting
                        ? null
                        : (_) => _toggleSelection(recording.id),
                  )
                : IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: _isSubmitting
                        ? null
                        : () => _togglePlayback(recording),
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                    ),
                    tooltip: isPlaying
                        ? l10n(context).pausePlayback
                        : l10n(context).playRecording,
                  ),
            title: Text(
              recording.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    Text(
                      _formatDuration(recording.duration),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colors.onSurface),
                    ),
                    Text(
                      _formatDateTime(recording.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (isCurrent)
                  Text(
                    _playbackStateLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: colors.primary),
                  ),
              ],
            ),
            trailing: _isSelecting
                ? null
                : PopupMenuButton<String>(
                    tooltip: l10n(context).recordingActions,
                    onSelected: (action) {
                      if (action == 'rename') {
                        _renameRecording(recording);
                      } else if (action == 'move') {
                        _moveRecording(recording);
                      } else if (action == 'share') {
                        _shareRecording(recording);
                      } else if (action == 'delete') {
                        _deleteRecording(recording);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'rename',
                        enabled: !_libraryProtected,
                        child: Text(l10n(context).rename),
                      ),
                      PopupMenuItem(
                        value: 'move',
                        enabled: !_libraryProtected,
                        child: Text(l10n(context).moveToFolder),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: Text(l10n(context).share),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        enabled: !_libraryProtected,
                        child: Text(
                          l10n(context).delete,
                          style: TextStyle(
                            color: _libraryProtected
                                ? null
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget? _buildPlaybackControls(BuildContext context) {
    final recordingId = _playbackStatus.recordingId;
    if (recordingId == null) {
      return null;
    }
    final recording = _recordings.where((item) => item.id == recordingId);
    if (recording.isEmpty) {
      return null;
    }

    final activeRecording = recording.first;
    final isPlaying = _playbackStatus.state == PlaybackState.playing;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      key: const Key('libraryPlaybackControls'),
      color: colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: const Key('libraryPlaybackTitle'),
                onTap: () => _openRecordingDetail(activeRecording),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    activeRecording.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
              PlaybackProgress(
                recording: activeRecording,
                service: _playbackService,
                sliderKey: const Key('libraryPlaybackProgress'),
                trailing: IconButton(
                  onPressed:
                      _playbackStatus.state == PlaybackState.loading ||
                          _playbackService.isScrubbing
                      ? null
                      : () => _togglePlayback(activeRecording),
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                  ),
                  tooltip: isPlaying
                      ? l10n(context).pausePlayback
                      : l10n(context).playRecording,
                ),
              ),
              if (_playbackStatus.speed != 1)
                Text(
                  l10n(context).speedValue(_playbackStatus.speed.toString()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingControls(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final paused = _status.state == RecordingLifecycleState.paused;
    final recording =
        _status.state == RecordingLifecycleState.recording &&
        !_isCancellingRecording;
    final busy =
        _isCancellingRecording ||
        _status.state == RecordingLifecycleState.preparing ||
        _status.state == RecordingLifecycleState.stopping ||
        _status.state == RecordingLifecycleState.discarding;
    final stateIcon = busy
        ? Icons.hourglass_top_rounded
        : paused
        ? Icons.pause_rounded
        : recording
        ? Icons.mic_rounded
        : Icons.mic_none_rounded;

    return Scaffold(
      appBar: AppBar(
        leading: _hasActiveSession
            ? IconButton(
                key: const Key('recordingBack'),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: !_isSubmitting && _canStop
                    ? _confirmRecordingExit
                    : null,
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: Text(l10n(context).appTitle),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        actions: [
          PopupMenuButton<String>(
            key: const Key('recordingSettingsMenu'),
            tooltip: l10n(context).more,
            enabled: !_isSubmitting,
            onSelected: (_) => _openRecordingSettings(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'settings',
                child: Text(l10n(context).settings),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n(context).newRecording,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_status.format != null)
                        Text(
                          l10n(context).recordingFormat(_status.format!.label),
                          key: const Key('sessionRecordingFormat'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      const Spacer(),
                      Center(
                        child: Column(
                          children: [
                            ExcludeSemantics(
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: recording
                                      ? colorScheme.primaryContainer
                                      : colorScheme.surfaceContainerHighest,
                                ),
                                child: Icon(
                                  stateIcon,
                                  key: const Key('recordingStateIcon'),
                                  size: 32,
                                  color: recording
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _statusLabel,
                              key: const Key('recordingStateLabel'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: recording
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _formatDuration(_status.elapsed),
                                key: const Key('recordingElapsed'),
                                style: Theme.of(context).textTheme.displayLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                      color: colorScheme.onSurface,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (_permissionMessage != null) ...[
                        _MessagePanel(
                          icon: Icons.mic_off_rounded,
                          message: _permissionMessage!,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _isSubmitting ? null : _openAppSettings,
                            icon: const Icon(Icons.settings_outlined),
                            label: Text(l10n(context).openSystemSettings),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_serviceError != null) ...[
                        _MessagePanel(
                          icon: Icons.error_outline_rounded,
                          message: _serviceError!,
                          isError: true,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_successMessage != null) ...[
                        _MessagePanel(
                          icon: Icons.check_circle_outline_rounded,
                          message: _successMessage!,
                          onDismiss: _dismissSuccessMessage,
                          onAction:
                              _savedRecordingId != null &&
                                  !_libraryProtected &&
                                  !_isSubmitting
                              ? _renameSavedRecording
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_canStart)
                        SizedBox(
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: _isSubmitting
                                ? null
                                : _requestPermissionAndStart,
                            icon: const Icon(Icons.mic_rounded),
                            label: Text(
                              _permissionMessage == null
                                  ? l10n(context).startRecording
                                  : l10n(context).requestAgain,
                            ),
                          ),
                        )
                      else if (_hasActiveSession || _isCancellingRecording)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      key: const Key('recordingPauseResume'),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(48, 56),
                                      ),
                                      onPressed:
                                          !_isSubmitting &&
                                              (_canPause || _canResume)
                                          ? _pauseOrResume
                                          : null,
                                      icon: Icon(
                                        paused
                                            ? Icons.play_arrow_rounded
                                            : Icons.pause_rounded,
                                      ),
                                      label: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // Reserve both labels so pausing never moves the controls.
                                          ExcludeSemantics(
                                            child: Opacity(
                                              opacity: 0,
                                              child: RichText(
                                                textScaler:
                                                    MediaQuery.textScalerOf(
                                                      context,
                                                    ),
                                                textAlign: TextAlign.center,
                                                text: TextSpan(
                                                  text: l10n(
                                                    context,
                                                  ).resumeRecording,
                                                  style: DefaultTextStyle.of(
                                                    context,
                                                  ).style,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            paused
                                                ? l10n(context).resumeRecording
                                                : l10n(context).pause,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      key: const Key('recordingStopSave'),
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(48, 56),
                                      ),
                                      onPressed: !_isSubmitting && _canStop
                                          ? _stopAndSave
                                          : null,
                                      icon: const Icon(Icons.stop_rounded),
                                      label: Text(
                                        l10n(context).stopAndSave,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: DestructiveActionButton(
                                key: const Key('recordingDiscard'),
                                filled: false,
                                onPressed: !_isSubmitting && _canCancel
                                    ? _confirmCancellation
                                    : null,
                                label: l10n(context).discardRecording,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _statusLabel => _isCancellingRecording
      ? l10n(context).recordingDiscarding
      : switch (_status.state) {
          RecordingLifecycleState.idle => l10n(context).recordingIdle,
          RecordingLifecycleState.preparing => l10n(context).recordingPreparing,
          RecordingLifecycleState.recording => l10n(context).recordingActive,
          RecordingLifecycleState.paused => l10n(context).recordingPaused,
          RecordingLifecycleState.stopping => l10n(context).recordingStopping,
          RecordingLifecycleState.discarding => l10n(
            context,
          ).recordingDiscarding,
          RecordingLifecycleState.failed => l10n(context).recordingFailed,
        };

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final paddedMinutes = minutes.toString().padLeft(2, '0');
    final paddedSeconds = seconds.toString().padLeft(2, '0');
    if (hours == 0) {
      return '$paddedMinutes:$paddedSeconds';
    }
    return '${hours.toString().padLeft(2, '0')}:$paddedMinutes:$paddedSeconds';
  }

  String get _playbackStateLabel => switch (_playbackStatus.state) {
    PlaybackState.playing => l10n(context).playing,
    PlaybackState.paused => l10n(context).playbackPaused,
    PlaybackState.loading => l10n(context).loadingPlayback,
    PlaybackState.failed => l10n(context).playbackFailed,
    PlaybackState.idle => l10n(context).notPlaying,
  };

  String _formatDateTime(DateTime dateTime) {
    final localTime = dateTime.toLocal();
    final month = localTime.month.toString().padLeft(2, '0');
    final day = localTime.day.toString().padLeft(2, '0');
    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');
    final year = localTime.year == DateTime.now().year
        ? ''
        : '${localTime.year}-';
    return '$year$month-$day $hour:$minute';
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.message,
    this.isError = false,
    this.onDismiss,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final bool isError;
  final VoidCallback? onDismiss;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = isError ? colorScheme.error : colorScheme.onSurface;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isError
            ? colorScheme.errorContainer
            : colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: foregroundColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    localizedMessage(context, message),
                    style: TextStyle(color: foregroundColor),
                  ),
                  if (onAction != null)
                    TextButton(
                      onPressed: onAction,
                      child: Text(l10n(context).rename),
                    ),
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                tooltip: l10n(context).dismissMessage,
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

class _RenameRecordingDialog extends StatefulWidget {
  const _RenameRecordingDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameRecordingDialog> createState() => _RenameRecordingDialogState();
}

class _RenameRecordingDialogState extends State<_RenameRecordingDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(l10n(context).renameRecording),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.pop(context, value),
        decoration: InputDecoration(labelText: l10n(context).recordingTitle),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n(context).cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n(context).save),
        ),
      ],
    );
  }
}

class _FolderManagementPage extends StatefulWidget {
  const _FolderManagementPage({
    required this.listFolders,
    required this.listRecordings,
    required this.createFolder,
    required this.renameFolder,
    required this.deleteFolder,
    required this.reorderFolders,
    required this.coordinator,
  });

  final Future<List<RecordingFolder>> Function() listFolders;
  final LibraryCoordinator coordinator;
  final Future<void> Function(List<String> ids) reorderFolders;
  final Future<List<Recording>> Function(String folderId) listRecordings;
  final Future<RecordingFolder> Function(String name) createFolder;
  final Future<void> Function(String folderId, String name) renameFolder;
  final Future<void> Function(String folderId, FolderDeletionAction? action)
  deleteFolder;

  @override
  State<_FolderManagementPage> createState() => _FolderManagementPageState();
}

class _FolderManagementPageState extends State<_FolderManagementPage> {
  late Future<List<RecordingFolder>> _folders = widget.listFolders();
  String? _errorMessage;
  List<RecordingFolder>? _draft;
  List<String> _originalIds = [];
  bool _savingOrder = false;
  bool get _protected => widget.coordinator.isProtected;

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_protectionChanged);
    _wasProtected = _protected;
  }

  bool _wasProtected = false;
  void _protectionChanged() {
    if (!mounted || _wasProtected == _protected) return;
    _wasProtected = _protected;
    setState(() {
      if (!_savingOrder) _draft = null;
      if (!_protected) _folders = widget.listFolders();
    });
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_protectionChanged);
    super.dispose();
  }

  void _cancelSort() {
    if (_savingOrder) return;
    setState(() {
      _draft = null;
      _errorMessage = null;
    });
  }

  void _moveFolder(int oldIndex, int newIndex) {
    if (_savingOrder || _draft == null) return;
    setState(() {
      final folder = _draft!.removeAt(oldIndex);
      _draft!.insert(newIndex, folder);
    });
  }

  Future<void> _saveOrder() async {
    if (_savingOrder || _draft == null) return;
    final ids = _draft!.map((folder) => folder.id).toList();
    if (List.generate(
      ids.length,
      (i) => ids[i] == _originalIds[i],
    ).every((same) => same)) {
      _cancelSort();
      return;
    }
    setState(() {
      _savingOrder = true;
      _errorMessage = null;
    });
    try {
      await widget.reorderFolders(ids);
      if (!mounted) return;
      setState(() {
        _folders = Future.value(List<RecordingFolder>.of(_draft!));
        _draft = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'folderOrderSaveFailed');
      }
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  Future<void> _createFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _CreateFolderDialog(),
    );
    final normalizedName = name?.trim();
    if (normalizedName == null || normalizedName.isEmpty || !mounted) {
      return;
    }

    try {
      await widget.createFolder(normalizedName);
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = null;
        _folders = widget.listFolders();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'createFolderFailed';
      });
    }
  }

  Future<void> _renameFolder(RecordingFolder folder) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameFolderDialog(initialName: folder.name),
    );
    final normalizedName = name?.trim();
    if (normalizedName == null || normalizedName.isEmpty || !mounted) {
      return;
    }

    try {
      await widget.renameFolder(folder.id, normalizedName);
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = null;
        _folders = widget.listFolders();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'renameFolderFailed';
      });
    }
  }

  Future<void> _deleteFolder(RecordingFolder folder) async {
    try {
      final recordings = await widget.listRecordings(folder.id);
      if (!mounted) {
        return;
      }
      FolderDeletionAction? action;
      if (recordings.isEmpty) {
        action = await showDialog<FolderDeletionAction?>(
          context: context,
          builder: (context) => _DeleteEmptyFolderDialog(folder: folder),
        );
      } else {
        action = await showDialog<FolderDeletionAction?>(
          context: context,
          builder: (context) => _DeleteNonEmptyFolderDialog(folder: folder),
        );
      }
      if (!mounted || (action == null && recordings.isNotEmpty)) {
        return;
      }
      if (recordings.isEmpty) {
        final confirmed = action == FolderDeletionAction.moveRecordingsToAll;
        if (!confirmed) {
          return;
        }
      }

      await widget.deleteFolder(folder.id, action);
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = null;
        _folders = widget.listFolders();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'deleteFolderFailed';
      });
    }
  }

  Widget _folderRow(RecordingFolder folder, int index, int count) {
    final sorting = _draft != null;
    final up = index > 0 && !_savingOrder && !_protected;
    final down = index < count - 1 && !_savingOrder && !_protected;
    return ListTile(
      key: ValueKey(folder.id),
      leading: const Icon(Icons.folder_outlined),
      title: Text(folder.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: sorting
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<String>(
                  key: Key('folderSortActions-${folder.id}'),
                  tooltip: l10n(context).moveFolderPosition(folder.name),
                  enabled: !_savingOrder,
                  onSelected: (action) => _moveFolder(
                    index,
                    action == 'up' ? index - 1 : index + 1,
                  ),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'up',
                      enabled: up,
                      child: Text(l10n(context).moveUp),
                    ),
                    PopupMenuItem(
                      value: 'down',
                      enabled: down,
                      child: Text(l10n(context).moveDown),
                    ),
                  ],
                ),
                Semantics(
                  label: l10n(context).reorderFolder(folder.name),
                  customSemanticsActions: {
                    if (up)
                      CustomSemanticsAction(label: l10n(context).moveUp): () =>
                          _moveFolder(index, index - 1),
                    if (down)
                      CustomSemanticsAction(
                        label: l10n(context).moveDown,
                      ): () =>
                          _moveFolder(index, index + 1),
                  },
                  child: ReorderableDragStartListener(
                    key: Key('folderDrag-${folder.id}'),
                    index: index,
                    enabled: !_savingOrder,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ),
              ],
            )
          : PopupMenuButton<String>(
              enabled: !_protected,
              key: Key('folderActions-${folder.id}'),
              tooltip: l10n(context).folderActions,
              onSelected: (action) {
                if (action == 'rename') _renameFolder(folder);
                if (action == 'delete') _deleteFolder(folder);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Text(l10n(context).rename),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    l10n(context).deleteFolder,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RecordingFolder>>(
      future: _folders,
      builder: (context, snapshot) {
        final folders = _draft ?? snapshot.data ?? const <RecordingFolder>[];
        final sorting = _draft != null;
        return PopScope(
          canPop: !sorting && !_savingOrder,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && sorting) _cancelSort();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                sorting
                    ? l10n(context).sortFolders
                    : l10n(context).manageFolders,
              ),
              automaticallyImplyLeading: !sorting,
              leading: sorting
                  ? IconButton(
                      key: const Key('cancelFolderSort'),
                      tooltip: l10n(context).cancelSorting,
                      onPressed: _savingOrder ? null : _cancelSort,
                      icon: const Icon(Icons.close),
                    )
                  : null,
              actions: [
                if (sorting)
                  TextButton(
                    key: const Key('saveFolderSort'),
                    onPressed: _savingOrder || _protected ? null : _saveOrder,
                    child: Text(l10n(context).done),
                  )
                else
                  TextButton(
                    key: const Key('startFolderSort'),
                    onPressed:
                        snapshot.connectionState != ConnectionState.done ||
                            _protected ||
                            snapshot.hasError ||
                            folders.length < 2
                        ? null
                        : () {
                            setState(() {
                              _draft = List.of(folders);
                              _originalIds = folders.map((f) => f.id).toList();
                              _errorMessage = null;
                            });
                          },
                    child: Text(l10n(context).sort),
                  ),
              ],
            ),
            body: snapshot.connectionState != ConnectionState.done && !sorting
                ? Center(child: CircularProgressIndicator())
                : snapshot.hasError && !sorting
                ? Center(child: Text(l10n(context).foldersReadFailed))
                : Column(
                    children: [
                      if (_protected)
                        const Flexible(
                          fit: FlexFit.loose,
                          child: SingleChildScrollView(
                            child: BackupProtectionNotice(),
                          ),
                        ),
                      if (sorting)
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(l10n(context).sortingDescription),
                        ),
                      if (_savingOrder) const LinearProgressIndicator(),
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                          child: Text(
                            localizedMessage(context, _errorMessage!),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      Expanded(
                        child: folders.isEmpty
                            ? Center(child: Text(l10n(context).noFolders))
                            : sorting
                            ? ReorderableListView.builder(
                                key: const Key('folderSortList'),
                                buildDefaultDragHandles: false,
                                itemCount: folders.length,
                                onReorder: (oldIndex, newIndex) {
                                  _moveFolder(
                                    oldIndex,
                                    newIndex > oldIndex
                                        ? newIndex - 1
                                        : newIndex,
                                  );
                                },
                                itemBuilder: (_, index) => _folderRow(
                                  folders[index],
                                  index,
                                  folders.length,
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 96),
                                itemCount: folders.length,
                                itemBuilder: (_, index) => _folderRow(
                                  folders[index],
                                  index,
                                  folders.length,
                                ),
                              ),
                      ),
                    ],
                  ),
            floatingActionButton: sorting
                ? null
                : FloatingActionButton.extended(
                    key: const Key('createFolderButton'),
                    onPressed: _protected ? null : _createFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: Text(l10n(context).createFolder),
                  ),
          ),
        );
      },
    );
  }
}

class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog();

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(l10n(context).createFolder),
      content: TextField(
        key: const Key('folderNameField'),
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.pop(context, value),
        decoration: InputDecoration(labelText: l10n(context).folderName),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n(context).cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n(context).create),
        ),
      ],
    );
  }
}

class _RenameFolderDialog extends StatefulWidget {
  const _RenameFolderDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameFolderDialog> createState() => _RenameFolderDialogState();
}

class _RenameFolderDialogState extends State<_RenameFolderDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(l10n(context).renameFolder),
      content: TextField(
        key: const Key('renameFolderNameField'),
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.pop(context, value),
        decoration: InputDecoration(labelText: l10n(context).folderName),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n(context).cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n(context).save),
        ),
      ],
    );
  }
}

class _DeleteEmptyFolderDialog extends StatelessWidget {
  const _DeleteEmptyFolderDialog({required this.folder});

  final RecordingFolder folder;

  @override
  Widget build(BuildContext context) {
    return DestructiveConfirmationDialog(
      title: l10n(context).deleteFolderTitle,
      message: l10n(context).emptyFolderDelete(folder.name),
      actionLabel: l10n(context).deleteFolder,
      onConfirm: () =>
          Navigator.pop(context, FolderDeletionAction.moveRecordingsToAll),
    );
  }
}

class _DeleteNonEmptyFolderDialog extends StatelessWidget {
  const _DeleteNonEmptyFolderDialog({required this.folder});

  final RecordingFolder folder;

  @override
  Widget build(BuildContext context) {
    return DestructiveConfirmationDialog(
      title: l10n(context).handleFolderRecordings,
      message: l10n(context).nonemptyFolderDelete(folder.name),
      actionLabel: l10n(context).moveToDeleted,
      onConfirm: () => Navigator.pop(
        context,
        FolderDeletionAction.moveRecordingsToRecentlyDeleted,
      ),
      alternativeAction: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: () =>
            Navigator.pop(context, FolderDeletionAction.moveRecordingsToAll),
        child: Text(l10n(context).moveToAll),
      ),
    );
  }
}
