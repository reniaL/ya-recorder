import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/main.dart';
import 'package:ya_recorder/playback/audio_playback_service.dart';
import 'package:ya_recorder/recording/recording_service.dart';
import 'package:ya_recorder/sharing/audio_share_service.dart';
import 'package:ya_recorder/storage/models/recording.dart';
import 'package:ya_recorder/storage/models/recording_folder.dart';
import 'package:ya_recorder/storage/recording_store.dart';

void main() {
  const commandChannel = MethodChannel(
    'io.github.renial.ya_recorder/recording_commands',
  );
  const eventChannel = MethodChannel(
    'io.github.renial.ya_recorder/recording_events',
  );

  late bool permissionGranted;
  late String initialState;
  late bool initialCanResume;
  late List<String> invokedMethods;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    permissionGranted = false;
    initialState = 'idle';
    initialCanResume = false;
    invokedMethods = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(commandChannel, (call) async {
      invokedMethods.add(call.method);
      switch (call.method) {
        case 'getStatus':
          return {
            'state': initialState,
            'elapsedMs': 0,
            'canResume': initialCanResume,
          };
        case 'requestMicrophonePermission':
          return permissionGranted;
        case 'start':
        case 'pause':
        case 'resume':
        case 'cancel':
        case 'openAppSettings':
          return null;
        default:
          throw PlatformException(code: 'unexpected-method');
      }
    });
    messenger.setMockMethodCallHandler(eventChannel, (call) async {
      if (call.method == 'listen' || call.method == 'cancel') {
        return null;
      }
      throw PlatformException(code: 'unexpected-event-method');
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(commandChannel, null);
    messenger.setMockMethodCallHandler(eventChannel, null);
  });

  testWidgets('denied microphone permission can be requested again', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        recordingService: RecordingService(
          commands: commandChannel,
          events: const EventChannel(
            'io.github.renial.ya_recorder/recording_events',
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('开始录音'));
    await tester.pump();

    expect(find.text('需要麦克风权限才能开始录音。'), findsOneWidget);
    expect(find.text('再次请求'), findsOneWidget);
    expect(invokedMethods, contains('requestMicrophonePermission'));

    await tester.tap(find.text('前往系统设置'));
    await tester.pump();
    expect(invokedMethods, contains('openAppSettings'));

    permissionGranted = true;
    await tester.tap(find.text('再次请求'));
    await tester.pump();

    expect(find.text('正在准备录音'), findsOneWidget);
    expect(invokedMethods, contains('start'));
  });

  testWidgets('recording can be paused', (WidgetTester tester) async {
    initialState = 'recording';
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('暂停'), findsOneWidget);
    await tester.tap(find.text('暂停'));
    await tester.pump();

    expect(invokedMethods, contains('pause'));
  });

  testWidgets('paused recording can resume', (WidgetTester tester) async {
    initialState = 'paused';
    initialCanResume = true;
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('继续录音'), findsOneWidget);
    await tester.tap(find.text('继续录音'));
    await tester.pump();

    expect(invokedMethods, contains('resume'));
  });

  testWidgets('saved recordings are shown in the all recordings list', (
    WidgetTester tester,
  ) async {
    final recordingStore = _RecordingStoreSpy()
      ..recordings = [
        Recording(
          id: 'recording-1',
          title: '项目讨论',
          filePath: '/private/recording-1.m4a',
          createdAt: DateTime.utc(2026, 9, 30, 8, 15),
          duration: const Duration(minutes: 1, seconds: 5),
          fileSizeBytes: 1024,
        ),
      ];

    await tester.pumpWidget(MyApp(recordingStore: recordingStore));
    await tester.pumpAndSettle();

    expect(find.text('全部录音'), findsOneWidget);
    expect(find.text('项目讨论'), findsOneWidget);
    expect(find.text('2026-09-30 16:15 · 01:05'), findsOneWidget);
  });

  testWidgets(
    'recently deleted opens from More and restored recordings refresh on return',
    (tester) async {
      final store = _RecordingStoreSpy()..recordings = [_recording('one')];
      await store.softDeleteRecording(
        recordingId: 'one',
        deletedAt: DateTime.now(),
      );
      final playback = AudioPlaybackService(backend: _FakePlaybackBackend());
      addTearDown(playback.dispose);
      await tester.pumpWidget(
        MyApp(recordingStore: store, playbackService: playback),
      );
      await tester.pumpAndSettle();
      expect(find.text('播放进度测试'), findsNothing);
      await tester.tap(find.byKey(const Key('manageFoldersMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('最近删除'));
      await tester.pumpAndSettle();
      expect(find.text('播放进度测试'), findsOneWidget);
      expect(find.text('开始录音'), findsNothing);
      await tester.tap(find.byTooltip('播放进度测试的操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(find.text('最近删除为空'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('全部录音'), findsOneWidget);
      expect(find.text('播放进度测试'), findsOneWidget);
    },
  );

  testWidgets('searches recording titles in the current scope', (
    WidgetTester tester,
  ) async {
    final recordingStore = _RecordingStoreSpy()
      ..recordings = [
        Recording(
          id: 'project',
          title: '项目讨论',
          filePath: '/private/project.m4a',
          createdAt: DateTime.utc(2026, 9, 30),
          duration: const Duration(minutes: 1),
          fileSizeBytes: 1024,
        ),
        Recording(
          id: 'interview',
          title: '客户访谈',
          filePath: '/private/interview.m4a',
          createdAt: DateTime.utc(2026, 9, 29),
          duration: const Duration(minutes: 1),
          fileSizeBytes: 1024,
        ),
      ];

    await tester.pumpWidget(MyApp(recordingStore: recordingStore));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recordingSearchButton')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('recordingSearchField')), '项目');
    await tester.pump();

    expect(find.text('项目讨论'), findsOneWidget);
    expect(find.text('客户访谈'), findsNothing);

    await tester.enterText(find.byKey(const Key('recordingSearchField')), '');
    await tester.pump();

    expect(find.text('项目讨论'), findsOneWidget);
    expect(find.text('客户访谈'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('recordingSearchField')),
      '不存在',
    );
    await tester.pump();

    expect(find.text('没有匹配的录音'), findsOneWidget);
  });

  testWidgets('bottom player displays and seeks playback progress', (
    WidgetTester tester,
  ) async {
    final playbackBackend = _FakePlaybackBackend();
    final recordingStore = _RecordingStoreSpy()
      ..recordings = [_recording('recording-1')];
    final playbackService = AudioPlaybackService(backend: playbackBackend);
    addTearDown(playbackService.dispose);

    await tester.pumpWidget(
      MyApp(recordingStore: recordingStore, playbackService: playbackService),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('播放录音'));
    await tester.pump();

    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('01:00'), findsAtLeastNWidgets(1));
    expect(find.byType(Slider), findsOneWidget);

    await tester.tap(find.byType(Slider));
    await tester.pump();

    expect(playbackBackend.seekPositions, isNotEmpty);
  });

  testWidgets('renames a recording from its action menu', (
    WidgetTester tester,
  ) async {
    final recordingStore = _RecordingStoreSpy()
      ..recordings = [_recording('recording-1')];
    await tester.pumpWidget(MyApp(recordingStore: recordingStore));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('录音操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();

    expect(find.text('重命名录音'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '会议记录');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('会议记录'), findsOneWidget);
    expect(
      recordingStore.recordings.single.filePath,
      '/private/recording-1.m4a',
    );
  });

  testWidgets('shares a recording from its action menu', (
    WidgetTester tester,
  ) async {
    final recordingStore = _RecordingStoreSpy()
      ..recordings = [_recording('recording-1')];
    final sharePlatform = _WidgetFakeAudioSharePlatform();
    await tester.pumpWidget(
      MyApp(
        recordingStore: recordingStore,
        audioShareService: AudioShareService(platform: sharePlatform),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('录音操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享'));
    await tester.pump();

    expect(sharePlatform.filePath, '/private/recording-1.m4a');
    expect(sharePlatform.fileName, '播放进度测试.m4a');
  });

  testWidgets('moves a recording to recently deleted after confirmation', (
    WidgetTester tester,
  ) async {
    final recordingStore = _RecordingStoreSpy()
      ..recordings = [_recording('recording-1')];
    await tester.pumpWidget(MyApp(recordingStore: recordingStore));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('录音操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('移入最近删除？'), findsOneWidget);
    expect(recordingStore.recordings.single.isDeleted, isFalse);

    await tester.tap(find.text('移入最近删除'));
    await tester.pumpAndSettle();

    expect(recordingStore.recordings.single.isDeleted, isTrue);
    expect(find.text('播放进度测试'), findsNothing);
  });

  testWidgets(
    'creates a uniquely named logical folder from folder management',
    (WidgetTester tester) async {
      final recordingStore = _RecordingStoreSpy();
      await tester.pumpWidget(MyApp(recordingStore: recordingStore));
      await tester.pump();

      await tester.tap(find.byKey(const Key('manageFoldersMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文件夹管理'));
      await tester.pumpAndSettle();
      expect(find.text('文件夹管理'), findsOneWidget);

      await tester.tap(find.byKey(const Key('createFolderButton')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('folderNameField')),
        '  Interviews  ',
      );
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      expect(recordingStore.folders.single.name, 'Interviews');
      expect(find.text('Interviews'), findsOneWidget);
    },
  );

  testWidgets('switches between all recordings and a selected folder', (
    WidgetTester tester,
  ) async {
    final recordingStore = _RecordingStoreSpy()
      ..folders = [
        RecordingFolder(
          id: 'folder-interviews',
          name: 'Interviews',
          createdAt: DateTime.utc(2026, 9, 30),
        ),
      ]
      ..recordings = [
        Recording(
          id: 'recording-in-folder',
          title: 'Interview',
          filePath: '/private/recording-in-folder.m4a',
          createdAt: DateTime.utc(2026, 9, 30),
          duration: const Duration(seconds: 30),
          fileSizeBytes: 1024,
          folderId: 'folder-interviews',
        ),
        Recording(
          id: 'recording-all',
          title: 'Inbox note',
          filePath: '/private/recording-all.m4a',
          createdAt: DateTime.utc(2026, 9, 29),
          duration: const Duration(seconds: 10),
          fileSizeBytes: 512,
        ),
      ];
    await tester.pumpWidget(MyApp(recordingStore: recordingStore));
    await tester.pumpAndSettle();

    expect(find.text('Interview'), findsOneWidget);
    expect(find.text('Inbox note'), findsOneWidget);

    await tester.tap(find.byKey(const Key('folderScopeSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('folderScope-folder-interviews')));
    await tester.pumpAndSettle();

    expect(find.text('Interviews'), findsOneWidget);
    expect(find.text('Interview'), findsOneWidget);
    expect(find.text('Inbox note'), findsNothing);

    await tester.tap(find.byKey(const Key('folderScopeSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('folderScope-all')));
    await tester.pumpAndSettle();

    expect(find.text('全部录音'), findsOneWidget);
    expect(find.text('Interview'), findsOneWidget);
    expect(find.text('Inbox note'), findsOneWidget);
  });

  testWidgets('moves a recording between a folder and all recordings', (
    WidgetTester tester,
  ) async {
    final recordingStore = _RecordingStoreSpy()
      ..folders = [
        RecordingFolder(
          id: 'folder-interviews',
          name: 'Interviews',
          createdAt: DateTime.utc(2026, 9, 30),
        ),
      ]
      ..recordings = [
        Recording(
          id: 'recording-1',
          title: 'Interview',
          filePath: '/private/recording-1.m4a',
          createdAt: DateTime.utc(2026, 9, 30),
          duration: const Duration(seconds: 30),
          fileSizeBytes: 1024,
        ),
      ];
    await tester.pumpWidget(MyApp(recordingStore: recordingStore));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('录音操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动到文件夹'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('moveRecording-recording-1-folder-interviews')),
    );
    await tester.pumpAndSettle();
    expect(recordingStore.recordings.single.folderId, 'folder-interviews');

    await tester.tap(find.byKey(const Key('folderScopeSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('folderScope-folder-interviews')));
    await tester.pumpAndSettle();
    expect(find.text('Interview'), findsOneWidget);

    await tester.tap(find.byTooltip('录音操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动到文件夹'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('moveRecording-recording-1-all')));
    await tester.pumpAndSettle();
    expect(recordingStore.recordings.single.folderId, isNull);
    expect(find.text('Interview'), findsNothing);
  });

  testWidgets(
    'renames and deletes a non-empty folder after choosing a disposition',
    (WidgetTester tester) async {
      final recordingStore = _RecordingStoreSpy()
        ..folders = [
          RecordingFolder(
            id: 'folder-project',
            name: 'Project',
            createdAt: DateTime.utc(2026, 9, 30),
          ),
        ]
        ..recordings = [
          Recording(
            id: 'recording-1',
            title: 'Project update',
            filePath: '/private/recording-1.m4a',
            createdAt: DateTime.utc(2026, 9, 30),
            duration: const Duration(seconds: 30),
            fileSizeBytes: 1024,
            folderId: 'folder-project',
          ),
        ];
      await tester.pumpWidget(MyApp(recordingStore: recordingStore));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('manageFoldersMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文件夹管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('folderActions-folder-project')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('renameFolderNameField')),
        '  Work  ',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(recordingStore.folders.single.name, 'Work');

      await tester.tap(find.byKey(const Key('folderActions-folder-project')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除文件夹'));
      await tester.pumpAndSettle();
      expect(find.text('处理文件夹中的录音'), findsOneWidget);
      await tester.tap(find.text('移至全部录音'));
      await tester.pumpAndSettle();

      expect(recordingStore.folders, isEmpty);
      expect(recordingStore.recordings.single.folderId, isNull);
    },
  );

  testWidgets(
    'batch delete requires confirmation and stops selected playback',
    (tester) async {
      final store = _RecordingStoreSpy()
        ..recordings = [_recording('one'), _recording('two')];
      final backend = _FakePlaybackBackend();
      final playback = AudioPlaybackService(backend: backend);
      addTearDown(playback.dispose);
      await tester.pumpWidget(
        MyApp(recordingStore: store, playbackService: playback),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('播放录音').first);
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('recordingRow-one')));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 条'), findsOneWidget);
      expect(find.text('开始录音'), findsNothing);
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(store.recordings.every((r) => !r.isDeleted), isTrue);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 条'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移入最近删除'));
      await tester.pumpAndSettle();
      expect(store.recordings.every((r) => r.isDeleted), isTrue);
      expect(playback.status.recordingId, isNull);
      expect(find.text('开始录音'), findsOneWidget);
    },
  );

  testWidgets(
    'select all only selects search results and query changes clear selection',
    (tester) async {
      final store = _RecordingStoreSpy()
        ..recordings = [
          _recording('one'),
          Recording(
            id: 'two',
            title: '其他录音',
            filePath: '/private/two.m4a',
            createdAt: DateTime.utc(2026),
            duration: Duration.zero,
            fileSizeBytes: 1,
          ),
        ];
      await tester.pumpWidget(MyApp(recordingStore: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('搜索录音'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('recordingSearchField')),
        '播放',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('多选录音'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 条'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('recordingSearchField')), '');
      await tester.pumpAndSettle();
      expect(find.text('已选 0 条'), findsOneWidget);
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 条'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byTooltip('多选录音'), findsOneWidget);
    },
  );

  testWidgets(
    'batch moves mixed folders then clears selection on scope change',
    (tester) async {
      final store = _RecordingStoreSpy()
        ..folders = [
          RecordingFolder(
            id: 'work',
            name: 'Work',
            createdAt: DateTime.utc(2026),
          ),
        ]
        ..recordings = [_recording('one'), _recording('two')];
      await store.moveRecording(recordingId: 'one', folderId: 'work');
      await tester.pumpWidget(MyApp(recordingStore: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('多选录音'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移动'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('batchMove-all')), findsOneWidget);
      await tester.tap(find.byKey(const Key('batchMove-work')));
      await tester.pumpAndSettle();
      expect(store.recordings.every((r) => r.folderId == 'work'), isTrue);
      await tester.longPress(find.byKey(const Key('recordingRow-one')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('folderScopeSelector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('folderScope-work')));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 条'), findsOneWidget);
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移动'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('batchMove-work')), findsNothing);
      await tester.tap(find.byKey(const Key('batchMove-all')));
      await tester.pumpAndSettle();
      expect(store.recordings.every((r) => r.folderId == null), isTrue);
      expect(find.byKey(const Key('recordingRow-one')), findsNothing);
    },
  );

  testWidgets('batch failure keeps selection for retry', (tester) async {
    final store = _RecordingStoreSpy()
      ..recordings = [_recording('one')]
      ..failBatchDelete = true;
    await tester.pumpWidget(MyApp(recordingStore: store));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('recordingRow-one')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移入最近删除'));
    await tester.pumpAndSettle();
    expect(find.text('无法批量删除录音，请重试。'), findsOneWidget);
    expect(find.text('已选 1 条'), findsOneWidget);
    expect(store.recordings.single.isDeleted, isFalse);
  });

  testWidgets(
    'batch submission locks selection and prevents duplicate operations',
    (tester) async {
      final gate = Completer<void>();
      final store = _RecordingStoreSpy()
        ..recordings = [_recording('one')]
        ..batchDeleteGate = gate.future;
      await tester.pumpWidget(MyApp(recordingStore: store));
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const Key('recordingRow-one')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移入最近删除'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(const Key('recordingRow-one')));
      await tester.tap(find.text('删除'));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('已选 1 条'), findsOneWidget);
      expect(store.batchDeleteCalls, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(store.recordings.single.isDeleted, isTrue);
      expect(find.byTooltip('多选录音'), findsOneWidget);
    },
  );

  testWidgets('selection controls fit a narrow screen with larger text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = _RecordingStoreSpy()..recordings = [_recording('one')];
    await tester.pumpWidget(MyApp(recordingStore: store));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('recordingRow-one')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('移动'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.byTooltip('退出多选'));
    await tester.pumpAndSettle();
    expect(find.text('开始录音'), findsOneWidget);
  });

  testWidgets(
    'success message can be dismissed without affecting errors or recordings',
    (tester) async {
      final events = StreamController<RecordingEvent>.broadcast();
      addTearDown(events.close);
      final store = _RecordingStoreSpy();
      await tester.pumpWidget(
        MyApp(
          recordingStore: store,
          recordingService: RecordingService(
            commands: commandChannel,
            eventStream: events.stream,
          ),
        ),
      );
      await tester.pumpAndSettle();
      events.add(_savedRecordingEvent('one'));
      await tester.pumpAndSettle();
      events.add(const RecordingFailed(code: 'test', message: '录音服务错误'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pumpAndSettle();
      expect(find.text('录音已保存'), findsNothing);
      expect(find.text('录音服务错误'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('录音服务错误'), findsOneWidget);
      expect(store.recordings.single.id, 'one');
    },
  );

  testWidgets(
    'new success message replaces the previous message and restarts expiry',
    (tester) async {
      final events = StreamController<RecordingEvent>.broadcast();
      addTearDown(events.close);
      await tester.pumpWidget(
        MyApp(
          recordingStore: _RecordingStoreSpy(),
          recordingService: RecordingService(
            commands: commandChannel,
            eventStream: events.stream,
          ),
        ),
      );
      await tester.pumpAndSettle();
      events.add(_savedRecordingEvent('one'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      events.add(_savedRecordingEvent('two'));
      await tester.pumpAndSettle();
      expect(find.text('录音已保存'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('录音已保存'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('录音已保存'), findsNothing);
    },
  );

  testWidgets(
    'starting the next recording clears the previous success message',
    (tester) async {
      final events = StreamController<RecordingEvent>.broadcast();
      addTearDown(events.close);
      final playback = AudioPlaybackService(backend: _FakePlaybackBackend());
      addTearDown(playback.dispose);
      await tester.pumpWidget(
        MyApp(
          recordingStore: _RecordingStoreSpy(),
          playbackService: playback,
          recordingService: RecordingService(
            commands: commandChannel,
            eventStream: events.stream,
          ),
        ),
      );
      await tester.pumpAndSettle();
      events.add(_savedRecordingEvent('one'));
      await tester.pumpAndSettle();
      permissionGranted = true;
      await tester.tap(find.text('开始录音'));
      await tester.pumpAndSettle();
      expect(invokedMethods, contains('start'));
      expect(find.text('录音已保存'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing the page cancels the success timer', (tester) async {
    final events = StreamController<RecordingEvent>.broadcast();
    addTearDown(events.close);
    await tester.pumpWidget(
      MyApp(
        recordingStore: _RecordingStoreSpy(),
        recordingService: RecordingService(
          commands: commandChannel,
          eventStream: events.stream,
        ),
      ),
    );
    await tester.pumpAndSettle();
    events.add(_savedRecordingEvent('one'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('interrupted save remains visible as an exception result', (
    tester,
  ) async {
    final events = StreamController<RecordingEvent>.broadcast();
    addTearDown(events.close);
    final store = _RecordingStoreSpy();
    await tester.pumpWidget(
      MyApp(
        recordingStore: store,
        recordingService: RecordingService(
          commands: commandChannel,
          eventStream: events.stream,
        ),
      ),
    );
    await tester.pumpAndSettle();
    events.add(_savedRecordingEvent('one', wasInterrupted: true));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('录音已中断，已录部分已保存。'), findsOneWidget);
    expect(find.text('录音已保存'), findsNothing);
    expect(find.byTooltip('关闭提示'), findsNothing);
    expect(store.recordings.single.wasInterrupted, isTrue);
  });

  testWidgets('stopped recording is written to the local index', (
    WidgetTester tester,
  ) async {
    final recordingStore = _RecordingStoreSpy();
    final recordingEvents = StreamController<RecordingEvent>.broadcast();
    addTearDown(recordingEvents.close);
    initialState = 'recording';

    await tester.pumpWidget(
      MyApp(
        recordingService: RecordingService(
          commands: commandChannel,
          eventStream: recordingEvents.stream,
        ),
        recordingStore: recordingStore,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('停止并保存'));
    await tester.pump();
    expect(invokedMethods, contains('stop'));
    expect(find.text('正在完成录音'), findsOneWidget);

    recordingEvents.add(
      RecordingSaved(
        SavedNativeRecording(
          id: 'recording-1',
          filePath: '/private/recording-1.m4a',
          createdAt: DateTime.utc(2026, 9, 30, 8, 15),
          duration: const Duration(seconds: 12),
          fileSizeBytes: 1024,
          wasInterrupted: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(recordingStore.savedRecording, isNotNull);
    expect(recordingStore.savedRecording!.id, 'recording-1');
    expect(
      recordingStore.savedRecording!.duration,
      const Duration(seconds: 12),
    );
    expect(find.text('录音已保存'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('录音已保存'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('录音已保存'), findsNothing);
    expect(recordingStore.savedRecording, isNotNull);
  });

  testWidgets(
    'confirmed cancellation returns to idle without saving an index',
    (WidgetTester tester) async {
      final recordingStore = _RecordingStoreSpy();
      final recordingEvents = StreamController<RecordingEvent>.broadcast();
      addTearDown(recordingEvents.close);
      initialState = 'recording';

      await tester.pumpWidget(
        MyApp(
          recordingService: RecordingService(
            commands: commandChannel,
            eventStream: recordingEvents.stream,
          ),
          recordingStore: recordingStore,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('放弃本次录音'));
      await tester.pumpAndSettle();
      expect(find.text('放弃这次录音？'), findsOneWidget);

      await tester.tap(find.text('放弃'));
      await tester.pump();
      expect(invokedMethods, contains('cancel'));

      recordingEvents.add(
        const RecordingStateChanged(
          RecordingSessionStatus(
            state: RecordingLifecycleState.discarding,
            elapsed: Duration.zero,
            canResume: false,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('正在放弃录音'), findsOneWidget);

      recordingEvents.add(
        const RecordingStateChanged(
          RecordingSessionStatus(
            state: RecordingLifecycleState.idle,
            elapsed: Duration.zero,
            canResume: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(recordingStore.savedRecording, isNull);
      expect(find.text('本次录音已放弃'), findsOneWidget);
      expect(find.text('开始录音'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('本次录音已放弃'), findsNothing);
    },
  );
}

class _RecordingStoreSpy extends RecordingStore {
  _RecordingStoreSpy()
    : super(databasePath: 'unused', databaseFactory: databaseFactoryFfi);

  Recording? savedRecording;
  List<Recording> recordings = const [];
  List<RecordingFolder> folders = const [];
  bool failBatchDelete = false;
  Future<void>? batchDeleteGate;
  int batchDeleteCalls = 0;

  @override
  Future<List<Recording>> listRecentlyDeleted() async =>
      recordings.where((r) => r.isDeleted).toList();

  @override
  Future<void> restoreRecording(String recordingId, {DateTime? now}) async {
    recordings = [
      for (final r in recordings)
        if (r.id == recordingId)
          Recording(
            id: r.id,
            title: r.title,
            filePath: r.filePath,
            createdAt: r.createdAt,
            duration: r.duration,
            fileSizeBytes: r.fileSizeBytes,
            folderId: r.folderId,
            wasInterrupted: r.wasInterrupted,
          )
        else
          r,
    ];
  }

  @override
  Future<void> moveRecordings({
    required Iterable<String> recordingIds,
    String? folderId,
  }) async {
    for (final id in recordingIds) {
      await moveRecording(recordingId: id, folderId: folderId);
    }
  }

  @override
  Future<void> softDeleteRecordings({
    required Iterable<String> recordingIds,
    required DateTime deletedAt,
  }) async {
    batchDeleteCalls++;
    if (batchDeleteGate != null) await batchDeleteGate;
    if (failBatchDelete) throw StateError('Simulated failure');
    for (final id in recordingIds) {
      await softDeleteRecording(recordingId: id, deletedAt: deletedAt);
    }
  }

  @override
  Future<RecordingFolder> createFolder({
    required String id,
    required String name,
    DateTime? createdAt,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty ||
        folders.any(
          (folder) => folder.name.toLowerCase() == normalizedName.toLowerCase(),
        )) {
      throw StateError('Folder name must be unique.');
    }
    final folder = RecordingFolder(
      id: id,
      name: normalizedName,
      createdAt: createdAt ?? DateTime.now().toUtc(),
    );
    folders = [...folders, folder];
    return folder;
  }

  @override
  Future<List<RecordingFolder>> listFolders() async => folders;

  @override
  Future<List<Recording>> listRecordings({String? folderId}) async {
    return recordings
        .where(
          (recording) =>
              !recording.isDeleted &&
              (folderId == null || recording.folderId == folderId),
        )
        .toList();
  }

  @override
  Future<void> moveRecording({
    required String recordingId,
    String? folderId,
  }) async {
    if (folderId != null && !folders.any((folder) => folder.id == folderId)) {
      throw StateError('Folder does not exist.');
    }
    recordings = [
      for (final recording in recordings)
        if (recording.id == recordingId)
          Recording(
            id: recording.id,
            title: recording.title,
            filePath: recording.filePath,
            createdAt: recording.createdAt,
            duration: recording.duration,
            fileSizeBytes: recording.fileSizeBytes,
            folderId: folderId,
            deletedAt: recording.deletedAt,
            wasInterrupted: recording.wasInterrupted,
          )
        else
          recording,
    ];
  }

  @override
  Future<void> renameFolder({
    required String folderId,
    required String name,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty ||
        folders.any(
          (folder) =>
              folder.id != folderId &&
              folder.name.toLowerCase() == normalizedName.toLowerCase(),
        )) {
      throw StateError('Folder name must be unique.');
    }
    folders = [
      for (final folder in folders)
        if (folder.id == folderId)
          RecordingFolder(
            id: folder.id,
            name: normalizedName,
            createdAt: folder.createdAt,
          )
        else
          folder,
    ];
  }

  @override
  Future<void> deleteFolder({
    required String folderId,
    FolderDeletionAction? action,
    DateTime? deletedAt,
  }) async {
    final activeRecordings = recordings
        .where(
          (recording) => recording.folderId == folderId && !recording.isDeleted,
        )
        .toList();
    if (activeRecordings.isNotEmpty && action == null) {
      throw StateError('A disposition is required.');
    }
    final now = (deletedAt ?? DateTime.now()).toUtc();
    recordings = [
      for (final recording in recordings)
        if (recording.folderId == folderId && !recording.isDeleted)
          Recording(
            id: recording.id,
            title: recording.title,
            filePath: recording.filePath,
            createdAt: recording.createdAt,
            duration: recording.duration,
            fileSizeBytes: recording.fileSizeBytes,
            folderId: null,
            deletedAt:
                action == FolderDeletionAction.moveRecordingsToRecentlyDeleted
                ? now
                : recording.deletedAt,
            wasInterrupted: recording.wasInterrupted,
          )
        else
          recording,
    ];
    folders = folders.where((folder) => folder.id != folderId).toList();
  }

  @override
  Future<void> saveRecording(Recording recording) async {
    savedRecording = recording;
    recordings = [recording, ...recordings];
  }

  @override
  Future<void> renameRecording({
    required String recordingId,
    required String title,
  }) async {
    recordings = [
      for (final recording in recordings)
        if (recording.id == recordingId)
          Recording(
            id: recording.id,
            title: title.trim(),
            filePath: recording.filePath,
            createdAt: recording.createdAt,
            duration: recording.duration,
            fileSizeBytes: recording.fileSizeBytes,
            folderId: recording.folderId,
            deletedAt: recording.deletedAt,
            wasInterrupted: recording.wasInterrupted,
          )
        else
          recording,
    ];
  }

  @override
  Future<void> softDeleteRecording({
    required String recordingId,
    required DateTime deletedAt,
  }) async {
    recordings = [
      for (final recording in recordings)
        if (recording.id == recordingId)
          Recording(
            id: recording.id,
            title: recording.title,
            filePath: recording.filePath,
            createdAt: recording.createdAt,
            duration: recording.duration,
            fileSizeBytes: recording.fileSizeBytes,
            folderId: recording.folderId,
            deletedAt: deletedAt.toUtc(),
            wasInterrupted: recording.wasInterrupted,
          )
        else
          recording,
    ];
  }
}

Recording _recording(String id) {
  return Recording(
    id: id,
    title: '播放进度测试',
    filePath: '/private/$id.m4a',
    createdAt: DateTime.utc(2026, 9, 30),
    duration: const Duration(minutes: 1),
    fileSizeBytes: 1024,
  );
}

RecordingSaved _savedRecordingEvent(String id, {bool wasInterrupted = false}) {
  return RecordingSaved(
    SavedNativeRecording(
      id: id,
      filePath: '/private/$id.m4a',
      createdAt: DateTime.utc(2026, 10, 5),
      duration: const Duration(seconds: 12),
      fileSizeBytes: 1024,
      wasInterrupted: wasInterrupted,
    ),
  );
}

class _WidgetFakeAudioSharePlatform implements AudioSharePlatform {
  String? filePath;
  String? fileName;

  @override
  Future<void> shareM4a({
    required String filePath,
    required String fileName,
    required String title,
  }) async {
    this.filePath = filePath;
    this.fileName = fileName;
  }
}

class _FakePlaybackBackend implements AudioPlaybackBackend {
  final StreamController<AudioBackendState> _stateController =
      StreamController<AudioBackendState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final List<Duration> seekPositions = [];

  @override
  Stream<AudioBackendState> get states => _stateController.stream;

  @override
  Stream<Duration> get positions => _positionController.stream;

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
  }

  @override
  Future<void> setFilePath(String filePath) async {}

  @override
  Future<void> stop() async {}
}
