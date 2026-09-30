import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/main.dart';
import 'package:ya_recorder/playback/audio_playback_service.dart';
import 'package:ya_recorder/recording/recording_service.dart';
import 'package:ya_recorder/storage/models/recording.dart';
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

  testWidgets('bottom player displays and seeks playback progress', (
    WidgetTester tester,
  ) async {
    final playbackBackend = _FakePlaybackBackend();
    final recordingStore = _RecordingStoreSpy()
      ..recordings = [_recording('recording-1')];
    final playbackService = AudioPlaybackService(backend: playbackBackend);
    addTearDown(playbackService.dispose);

    await tester.pumpWidget(
      MyApp(
        recordingStore: recordingStore,
        playbackService: playbackService,
      ),
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
    },
  );
}

class _RecordingStoreSpy extends RecordingStore {
  _RecordingStoreSpy()
    : super(databasePath: 'unused', databaseFactory: databaseFactoryFfi);

  Recording? savedRecording;
  List<Recording> recordings = const [];

  @override
  Future<List<Recording>> listRecordings({String? folderId}) async {
    return recordings;
  }

  @override
  Future<void> saveRecording(Recording recording) async {
    savedRecording = recording;
    recordings = [recording, ...recordings];
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
