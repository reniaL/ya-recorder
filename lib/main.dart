import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'playback/audio_playback_service.dart';
import 'playback/recording_detail_page.dart';
import 'recording/recording_service.dart';
import 'sharing/audio_share_service.dart';
import 'storage/recently_deleted_page.dart';
import 'storage/app_storage_paths.dart';
import 'storage/models/recording.dart';
import 'storage/models/recording_folder.dart';
import 'storage/recording_store.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '丫丫录音',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff0b6657),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff2f7f4),
        useMaterial3: true,
      ),
      home: RecordingHomePage(
        recordingService: recordingService ?? RecordingService(),
        recordingStore: recordingStore,
        playbackService: playbackService,
        audioShareService: audioShareService,
      ),
    );
  }
}

class RecordingHomePage extends StatefulWidget {
  const RecordingHomePage({
    super.key,
    required this.recordingService,
    this.recordingStore,
    this.playbackService,
    this.audioShareService,
  });

  final RecordingService recordingService;
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
  bool _isCancellingRecording = false;
  bool _isLoadingRecordings = true;
  bool _isSearching = false;
  bool _isSelecting = false;
  bool _isApplyingBatch = false;
  final Set<String> _selectedRecordingIds = {};
  String? _permissionMessage;
  String? _serviceError;
  String? _successMessage;
  Timer? _successMessageTimer;
  String? _libraryError;
  String? _playbackError;
  List<Recording> _recordings = const [];
  String _searchQuery = '';
  String? _selectedFolderId;
  String? _selectedFolderName;
  Future<RecordingStore>? _openedRecordingStore;

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
    _playbackSubscription = _playbackService.statuses.listen(
      _handlePlaybackStatus,
    );
    _eventSubscription = widget.recordingService.events.listen(
      _handleRecordingEvent,
      onError: _handleEventError,
    );
    _loadCurrentStatus();
    _initializeLibrary();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _successMessageTimer?.cancel();
    _eventSubscription.cancel();
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
    }
  }

  Future<void> _initializeLibrary() async {
    await _loadRecordings();
    await _cleanupExpiredRecordings();
  }

  Future<void> _cleanupExpiredRecordings() async {
    try {
      final failures = await (await _getRecordingStore())
          .purgeExpiredRecordings();
      if (failures.isNotEmpty) {
        _setServiceError('部分过期录音未能清理，请在最近删除中重试。');
      }
    } catch (_) {
      _setServiceError('无法清理过期录音，请在最近删除中重试。');
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
      _setLibraryError('无法打开最近删除。');
    }
  }

  // Called inside setState so replacement and clearing render together with
  // the recording state. Only one success message and timer may exist.
  void _updateSuccessMessage(String? message) {
    _successMessageTimer?.cancel();
    _successMessageTimer = null;
    _successMessage = message;
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
      _setServiceError(error.message ?? '无法读取当前录音状态。');
    } on FormatException catch (error) {
      _setServiceError(error.message);
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
        _libraryError = '无法读取本地录音。';
      });
    }
  }

  Future<void> _chooseFolderScope() async {
    try {
      final folders = await (await _getRecordingStore()).listFolders();
      if (!mounted) {
        return;
      }
      final selectedFolderId = await showModalBottomSheet<String?>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('选择录音范围')),
              ListTile(
                key: const Key('folderScope-all'),
                leading: const Icon(Icons.library_music_outlined),
                title: const Text('全部录音'),
                trailing: _selectedFolderId == null
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, ''),
              ),
              for (final folder in folders)
                ListTile(
                  key: Key('folderScope-${folder.id}'),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name),
                  trailing: _selectedFolderId == folder.id
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, folder.id),
                ),
            ],
          ),
        ),
      );
      if (!mounted || selectedFolderId == null) {
        return;
      }
      final folderId = selectedFolderId.isEmpty ? null : selectedFolderId;
      if (folderId == _selectedFolderId) {
        return;
      }

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
      _setLibraryError('无法读取文件夹。');
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
      await _audioShareService.shareRecording(recording);
    } catch (_) {
      _setServiceError('无法分享该录音。');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _renameRecording(Recording recording) async {
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
      await _loadRecordings();
    } catch (_) {
      _setServiceError('无法重命名该录音。');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _moveRecording(Recording recording) async {
    try {
      final folders = await (await _getRecordingStore()).listFolders();
      if (!mounted) {
        return;
      }
      final destinations = folders
          .where((folder) => folder.id != recording.folderId)
          .toList();
      if (recording.folderId == null && destinations.isEmpty) {
        _setServiceError('请先创建一个文件夹，再移动录音。');
        return;
      }

      final selectedFolderId = await showModalBottomSheet<String?>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('移动录音到')),
              if (recording.folderId != null)
                ListTile(
                  key: Key('moveRecording-${recording.id}-all'),
                  leading: const Icon(Icons.library_music_outlined),
                  title: const Text('全部录音'),
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
      await _loadRecordings();
    } catch (_) {
      _setServiceError('无法移动该录音。');
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
      builder: (context) => AlertDialog(
        title: const Text('移入最近删除？'),
        content: const Text('录音会保留在最近删除中，可在保留期内恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移入最近删除'),
          ),
        ],
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
      _setServiceError('无法删除该录音。');
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
          builder: (context) => AlertDialog(
            title: Text('将 ${ids.length} 条录音移入最近删除？'),
            content: const Text('录音会保留在最近删除中，可在保留期内恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('移入最近删除'),
              ),
            ],
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
          _setServiceError('请先创建一个文件夹，再移动录音。');
          return;
        }
        final destination = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(title: Text('移动 ${ids.length} 条录音到')),
                  if (canMoveToAll)
                    ListTile(
                      key: const Key('batchMove-all'),
                      title: const Text('全部录音'),
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
      _setServiceError(delete ? '无法批量删除录音，请重试。' : '无法批量移动录音，请重试。');
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _FolderManagementPage(
          listFolders: () async => (await _getRecordingStore()).listFolders(),
          listRecordings: (folderId) async =>
              (await _getRecordingStore()).listRecordings(folderId: folderId),
          createFolder: (name) async {
            final store = await _getRecordingStore();
            return store.createFolder(
              id: 'folder-${DateTime.now().microsecondsSinceEpoch}',
              name: name,
            );
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
      _setLibraryError('无法刷新文件夹。');
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
      await _playbackService.stop();
      final granted = await widget.recordingService
          .requestMicrophonePermission();
      if (!mounted) {
        return;
      }
      if (!granted) {
        setState(() {
          _permissionMessage = '需要麦克风权限才能开始录音。';
        });
        return;
      }

      setState(() {
        _status = const RecordingSessionStatus(
          state: RecordingLifecycleState.preparing,
          elapsed: Duration.zero,
          canResume: false,
        );
      });
      await widget.recordingService.start();
    } on PlatformException catch (error) {
      _setServiceError(error.message ?? '无法开始录音。');
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
      _setServiceError(error.message ?? '无法打开系统设置。');
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
      _setServiceError(error.message ?? '无法更新录音状态。');
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
      );
    });
    try {
      await widget.recordingService.stop();
    } on PlatformException catch (error) {
      _setServiceError(error.message ?? '无法停止录音。');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _confirmCancellation() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('放弃这次录音？'),
          content: const Text('当前未保存的内容将被删除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续录音'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放弃'),
            ),
          ],
        );
      },
    );
    if (shouldCancel != true || !mounted) {
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
          _serviceError = error.message ?? '无法放弃当前录音。';
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

  void _handleRecordingEvent(RecordingEvent event) {
    if (!mounted) {
      return;
    }

    switch (event) {
      case RecordingStateChanged(:final status):
        setState(() {
          final cancellationCompleted =
              _isCancellingRecording &&
              status.state == RecordingLifecycleState.idle;
          _status = status;
          if (status.state != RecordingLifecycleState.failed) {
            _serviceError = null;
          }
          if (cancellationCompleted) {
            _isCancellingRecording = false;
            _updateSuccessMessage('本次录音已放弃');
          }
        });
      case RecordingSaved(:final recording):
        unawaited(_persistSavedRecording(recording));
      case RecordingFailed(:final message):
        setState(() {
          _isCancellingRecording = false;
          _serviceError = message;
        });
    }
  }

  void _handleEventError(Object error, StackTrace stackTrace) {
    _setServiceError('无法连接录音服务。');
  }

  void _setServiceError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _serviceError = message;
    });
  }

  Future<void> _persistSavedRecording(
    SavedNativeRecording savedRecording,
  ) async {
    setState(() {
      _isPersistingRecording = true;
      _updateSuccessMessage(null);
      _serviceError = null;
    });

    try {
      final store = await _getRecordingStore();
      await store.saveRecording(
        Recording(
          id: savedRecording.id,
          title: _defaultTitle(savedRecording.createdAt),
          filePath: savedRecording.filePath,
          createdAt: savedRecording.createdAt,
          duration: savedRecording.duration,
          fileSizeBytes: savedRecording.fileSizeBytes,
          wasInterrupted: savedRecording.wasInterrupted,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isPersistingRecording = false;
        _status = _idleStatus;
        if (savedRecording.wasInterrupted) {
          _serviceError = '录音已中断，已录部分已保存。';
        } else {
          _updateSuccessMessage('录音已保存');
        }
      });
      await _loadRecordings();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPersistingRecording = false;
        _serviceError = '无法将录音保存到本地索引。';
      });
    }
  }

  Future<RecordingStore> _getRecordingStore() {
    final recordingStore = widget.recordingStore;
    if (recordingStore != null) {
      return Future.value(recordingStore);
    }

    return _openedRecordingStore ??= _openDefaultRecordingStore();
  }

  static Future<RecordingStore> _openDefaultRecordingStore() async {
    final paths = await AppStoragePaths.create();
    final store = RecordingStore(databasePath: paths.databasePath);
    await store.open();
    return store;
  }

  static String _defaultTitle(DateTime createdAt) {
    final localTime = createdAt.toLocal();
    final month = localTime.month.toString().padLeft(2, '0');
    final day = localTime.day.toString().padLeft(2, '0');
    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');
    return '录音 ${localTime.year}-$month-$day $hour:$minute';
  }

  bool get _canStart =>
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

  bool get _canPause => _status.state == RecordingLifecycleState.recording;

  bool get _canResume =>
      _status.state == RecordingLifecycleState.paused && _status.canResume;

  bool get _canStop =>
      _status.state == RecordingLifecycleState.recording ||
      _status.state == RecordingLifecycleState.paused;

  bool get _canCancel => switch (_status.state) {
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

    return _buildRecordingControls(context);
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
                    hintText: _selectedFolderName == null
                        ? '搜索全部录音'
                        : '搜索「$_selectedFolderName」中的录音',
                    border: InputBorder.none,
                  ),
                )
              : Semantics(
                  label: '${_selectedFolderName ?? '全部录音'}，切换录音范围',
                  button: true,
                  enabled: !_isSubmitting,
                  onTap: _isSubmitting ? null : _chooseFolderScope,
                  child: ExcludeSemantics(
                    child: TextButton(
                      key: const Key('folderScopeSelector'),
                      onPressed: _isSubmitting ? null : _chooseFolderScope,
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
                              _selectedFolderName ?? '全部录音',
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
          titleSpacing: 24,
          centerTitle: false,
          backgroundColor: Colors.transparent,
          actions: [
            if (_isSelecting)
              IconButton(
                tooltip: '退出多选',
                onPressed: _isSubmitting ? null : _exitSelection,
                icon: const Icon(Icons.close),
              ),
            if (!_isSelecting)
              IconButton(
                tooltip: '多选录音',
                onPressed: _isSubmitting || _visibleRecordings.isEmpty
                    ? null
                    : () => setState(() => _isSelecting = true),
                icon: const Icon(Icons.checklist),
              ),
            IconButton(
              key: const Key('recordingSearchButton'),
              tooltip: _isSearching ? '关闭搜索' : '搜索录音',
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
              tooltip: '更多',
              onSelected: (action) {
                if (action == 'folders') {
                  _openFolderManagement();
                } else if (action == 'recentlyDeleted') {
                  _openRecentlyDeleted();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  key: Key('manageFoldersItem'),
                  value: 'folders',
                  child: Text('文件夹管理'),
                ),
                PopupMenuItem(value: 'recentlyDeleted', child: Text('最近删除')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_permissionMessage != null ||
                  _serviceError != null ||
                  _successMessage != null ||
                  _playbackError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                            label: const Text('前往系统设置'),
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
                                '已选 ${_selectedRecordingIds.length} 条',
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
                                    ? '取消全选'
                                    : '全选',
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
                                label: const Text('移动'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    _isSubmitting ||
                                        _selectedRecordingIds.isEmpty
                                    ? null
                                    : () => _operateOnSelection(delete: true),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('删除'),
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
                onPressed: _isSubmitting ? null : _requestPermissionAndStart,
                icon: const Icon(Icons.mic_rounded),
                label: Text(_permissionMessage == null ? '开始录音' : '再次请求'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingList(BuildContext context) {
    if (_isLoadingRecordings) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_libraryError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48),
              const SizedBox(height: 16),
              Text(_libraryError!),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loadRecordings,
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
    }

    if (_recordings.isEmpty) {
      return Center(
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
              Text('还没有录音', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('点击“开始录音”录下第一段声音。'),
            ],
          ),
        ),
      );
    }

    final visibleRecordings = _visibleRecordings;
    if (visibleRecordings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, size: 56),
              const SizedBox(height: 16),
              const Text('没有匹配的录音'),
              const SizedBox(height: 8),
              const Text('请尝试其他标题关键词。'),
            ],
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
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final recording = visibleRecordings[index];
          final isPlaying =
              _playbackStatus.recordingId == recording.id &&
              _playbackStatus.state == PlaybackState.playing;
          return ListTile(
            key: Key('recordingRow-${recording.id}'),
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
                    semanticLabel: '选择 ${recording.title}',
                    onChanged: _isSubmitting
                        ? null
                        : (_) => _toggleSelection(recording.id),
                  )
                : const Icon(Icons.graphic_eq_rounded),
            title: Text(
              recording.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_formatDateTime(recording.createdAt)} · '
              '${_formatDuration(recording.duration)}',
            ),
            trailing: _isSelecting
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _togglePlayback(recording),
                        icon: Icon(
                          isPlaying
                              ? Icons.pause_circle_outline_rounded
                              : Icons.play_circle_outline_rounded,
                        ),
                        tooltip: isPlaying ? '暂停播放' : '播放录音',
                      ),
                      PopupMenuButton<String>(
                        tooltip: '录音操作',
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
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'rename', child: Text('重命名')),
                          PopupMenuItem(value: 'move', child: Text('移动到文件夹')),
                          PopupMenuItem(value: 'share', child: Text('分享')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
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
    final total = activeRecording.duration;
    final position = _playbackStatus.position > total
        ? total
        : _playbackStatus.position;
    final isPlaying = _playbackStatus.state == PlaybackState.playing;
    final canSeek =
        _playbackStatus.state != PlaybackState.loading &&
        _playbackStatus.state != PlaybackState.failed;
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
              Semantics(
                label: '播放进度',
                child: Slider(
                  value: position.inMilliseconds.toDouble(),
                  max: (total.inMilliseconds > 0 ? total.inMilliseconds : 1)
                      .toDouble(),
                  onChanged: canSeek
                      ? (value) => _playbackService.seek(
                          Duration(milliseconds: value.round()),
                        )
                      : null,
                ),
              ),
              Row(
                children: [
                  Expanded(child: Text(_formatDuration(position))),
                  Text(_formatDuration(total)),
                  IconButton(
                    onPressed: _playbackStatus.state == PlaybackState.loading
                        ? null
                        : () => _togglePlayback(activeRecording),
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                    ),
                    tooltip: isPlaying ? '暂停播放' : '播放录音',
                  ),
                ],
              ),
              if (_playbackStatus.speed != 1)
                Text('播放倍速 ${_playbackStatus.speed}×'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingControls(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('丫丫录音'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('新的录音', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                _statusLabel,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    Text(
                      _formatDuration(_status.elapsed),
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Icon(
                      _hasActiveSession
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
                      size: 52,
                      color: _hasActiveSession
                          ? const Color(0xffd5543f)
                          : colorScheme.primary,
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
                    label: const Text('前往系统设置'),
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
                    label: Text(_permissionMessage == null ? '开始录音' : '再次请求'),
                  ),
                )
              else if (_canPause || _canResume || _canStop || _canCancel)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_canPause || _canResume || _canStop)
                      Row(
                        children: [
                          if (_canPause || _canResume)
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _isSubmitting
                                    ? null
                                    : _pauseOrResume,
                                icon: Icon(
                                  _canPause
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                label: Text(_canPause ? '暂停' : '继续录音'),
                              ),
                            ),
                          if ((_canPause || _canResume) && _canStop)
                            const SizedBox(width: 12),
                          if (_canStop)
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _isSubmitting ? null : _stopAndSave,
                                icon: const Icon(Icons.stop_rounded),
                                label: const Text('停止并保存'),
                              ),
                            ),
                        ],
                      ),
                    if ((_canPause || _canResume || _canStop) && _canCancel)
                      const SizedBox(height: 12),
                    if (_canCancel)
                      OutlinedButton.icon(
                        onPressed: _isSubmitting ? null : _confirmCancellation,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('放弃本次录音'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _statusLabel => switch (_status.state) {
    RecordingLifecycleState.idle => '准备好后即可开始录音',
    RecordingLifecycleState.preparing => '正在准备录音',
    RecordingLifecycleState.recording => '正在录音',
    RecordingLifecycleState.paused => '录音已暂停',
    RecordingLifecycleState.stopping => '正在完成录音',
    RecordingLifecycleState.discarding => '正在放弃录音',
    RecordingLifecycleState.failed => '录音服务需要重新开始',
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

  String _formatDateTime(DateTime dateTime) {
    final localTime = dateTime.toLocal();
    final month = localTime.month.toString().padLeft(2, '0');
    final day = localTime.day.toString().padLeft(2, '0');
    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');
    return '${localTime.year}-$month-$day $hour:$minute';
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.message,
    this.isError = false,
    this.onDismiss,
  });

  final IconData icon;
  final String message;
  final bool isError;
  final VoidCallback? onDismiss;

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
              child: Text(message, style: TextStyle(color: foregroundColor)),
            ),
            if (onDismiss != null)
              IconButton(
                tooltip: '关闭提示',
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
      title: const Text('重命名录音'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.pop(context, value),
        decoration: const InputDecoration(labelText: '录音标题'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('保存'),
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
  });

  final Future<List<RecordingFolder>> Function() listFolders;
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
        _errorMessage = '无法创建文件夹。名称不能为空且必须唯一。';
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
        _errorMessage = '无法重命名文件夹。名称不能为空且必须唯一。';
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
        _errorMessage = '无法删除文件夹。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文件夹管理')),
      body: FutureBuilder<List<RecordingFolder>>(
        future: _folders,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('无法读取文件夹。'));
          }
          final folders = snapshot.data ?? const <RecordingFolder>[];
          return Column(
            children: [
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: folders.isEmpty
                    ? const Center(child: Text('还没有文件夹。'))
                    : ListView.builder(
                        itemCount: folders.length,
                        itemBuilder: (context, index) {
                          final folder = folders[index];
                          return ListTile(
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(folder.name),
                            trailing: PopupMenuButton<String>(
                              key: Key('folderActions-${folder.id}'),
                              tooltip: '文件夹操作',
                              onSelected: (action) {
                                if (action == 'rename') {
                                  _renameFolder(folder);
                                } else if (action == 'delete') {
                                  _deleteFolder(folder);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('重命名'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除文件夹'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('createFolderButton'),
        onPressed: _createFolder,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('创建文件夹'),
      ),
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
      title: const Text('创建文件夹'),
      content: TextField(
        key: const Key('folderNameField'),
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.pop(context, value),
        decoration: const InputDecoration(labelText: '文件夹名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('创建'),
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
      title: const Text('重命名文件夹'),
      content: TextField(
        key: const Key('renameFolderNameField'),
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.pop(context, value),
        decoration: const InputDecoration(labelText: '文件夹名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('保存'),
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
    return AlertDialog(
      title: const Text('删除文件夹？'),
      content: Text('“${folder.name}”为空文件夹，删除后无法恢复。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, FolderDeletionAction.moveRecordingsToAll),
          child: const Text('删除文件夹'),
        ),
      ],
    );
  }
}

class _DeleteNonEmptyFolderDialog extends StatelessWidget {
  const _DeleteNonEmptyFolderDialog({required this.folder});

  final RecordingFolder folder;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('处理文件夹中的录音'),
      content: Text('“${folder.name}”中仍有录音。删除前请选择这些录音的去向。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        OutlinedButton(
          onPressed: () =>
              Navigator.pop(context, FolderDeletionAction.moveRecordingsToAll),
          child: const Text('移至全部录音'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            FolderDeletionAction.moveRecordingsToRecentlyDeleted,
          ),
          child: const Text('移入最近删除'),
        ),
      ],
    );
  }
}
