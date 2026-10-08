import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/recording/recording_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('parses a native recording state event', () {
    final event = RecordingEvent.fromMap({
      'type': 'state',
      'state': 'paused',
      'elapsedMs': 1250,
      'canResume': true,
      'sessionId': 'session-1',
      'format': 'm4a',
    });

    expect(event, isA<RecordingStateChanged>());
    final stateChanged = event as RecordingStateChanged;
    expect(stateChanged.status.state, RecordingLifecycleState.paused);
    expect(stateChanged.status.elapsed, const Duration(milliseconds: 1250));
    expect(stateChanged.status.canResume, isTrue);
    expect(stateChanged.status.sessionId, 'session-1');
    expect(stateChanged.status.format, RecordingFormat.m4a);
  });

  test('parses a saved recording result', () {
    final event = RecordingEvent.fromMap({
      'type': 'fileReady',
      'recording': {
        'id': 'session-1',
        'filePath': '/data/recording-session-1.m4a',
        'createdAtMs': 1727568000000,
        'durationMs': 3000,
        'fileSizeBytes': 4096,
        'wasInterrupted': false,
        'format': 'm4a',
      },
    });

    expect(event, isA<RecordingFileReady>());
    final saved = event as RecordingFileReady;
    expect(saved.recording.id, 'session-1');
    expect(saved.recording.format, RecordingFormat.m4a);
    expect(saved.recording.duration, const Duration(seconds: 3));
    expect(saved.recording.fileSizeBytes, 4096);
    expect(saved.recording.wasInterrupted, isFalse);
    expect(saved.recording.createdAt, DateTime.utc(2024, 9, 29));
  });

  test('rejects unknown native lifecycle states', () {
    expect(
      () => RecordingSessionStatus.fromMap({
        'state': 'unknown',
        'elapsedMs': 0,
        'canResume': false,
      }),
      throwsFormatException,
    );
  });

  test('active sessions require explicit valid formats, idle has none', () {
    final active = <Object?, Object?>{
      'state': 'recording',
      'elapsedMs': 2000,
      'canResume': false,
      'sessionId': 'one',
      'format': 'mp3',
    };
    expect(RecordingSessionStatus.fromMap(active).format, RecordingFormat.mp3);
    for (final value in [null, 'wav', 'MP3', 1]) {
      expect(
        () => RecordingSessionStatus.fromMap({...active, 'format': value}),
        throwsFormatException,
      );
    }
    expect(
      RecordingSessionStatus.fromMap({
        'state': 'idle',
        'elapsedMs': 0,
        'canResume': false,
        'format': null,
      }).format,
      isNull,
    );
  });

  test('saved results carry format and reject misleading paths or formats', () {
    final result = <Object?, Object?>{
      'id': 'one',
      'filePath': '/private/one.mp3',
      'format': 'mp3',
      'createdAtMs': 0,
      'durationMs': 1000,
      'fileSizeBytes': 2000,
      'wasInterrupted': false,
    };
    expect(SavedNativeRecording.fromMap(result).format, RecordingFormat.mp3);
    for (final value in [null, 'wav', 42]) {
      expect(
        () => SavedNativeRecording.fromMap({...result, 'format': value}),
        throwsFormatException,
      );
    }
    for (final path in ['/private/one.m4a', '/private/one.mp3.part']) {
      expect(
        () => SavedNativeRecording.fromMap({...result, 'filePath': path}),
        throwsFormatException,
      );
    }
  });

  test('recovery parses explicit formats and rejects malformed results', () {
    final candidate = <Object?, Object?>{
      'id': 'one',
      'filePath': '/private/one.mp3',
      'format': 'mp3',
      'createdAtMs': 123,
      'durationMs': 3000,
      'fileSizeBytes': 128,
      'wasInterrupted': true,
    };
    final batch = RecordingRecoveryBatch.fromMap({
      'recordings': [candidate],
      'unresolvedCount': 1,
    });
    expect(batch.recordings.single.format, RecordingFormat.mp3);
    expect(batch.recordings.single.wasInterrupted, isTrue);
    expect(batch.unresolvedCount, 1);
    for (final bad in [
      {
        'recordings': [candidate],
        'unresolvedCount': -1,
      },
      {
        'recordings': [null],
        'unresolvedCount': 0,
      },
      {
        'recordings': [
          {...candidate, 'format': null},
        ],
        'unresolvedCount': 0,
      },
      {
        'recordings': [
          {...candidate, 'durationMs': 0},
        ],
        'unresolvedCount': 0,
      },
    ]) {
      expect(() => RecordingRecoveryBatch.fromMap(bad), throwsFormatException);
    }
  });

  test('recovery and index acknowledgement use distinct commands', () async {
    const channel = MethodChannel('recording-recovery-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'recoverRecordings'
          ? {'recordings': [], 'unresolvedCount': 0}
          : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = RecordingService(commands: channel);
    expect((await service.recoverRecordings()).recordings, isEmpty);
    await service.acknowledgeRecording('one');
    await service.deferRecording('two');
    expect(calls.map((c) => c.method), [
      'recoverRecordings',
      'acknowledgeRecording',
      'deferRecording',
    ]);
    expect(calls[1].arguments, {'id': 'one'});
    expect(calls[2].arguments, {'id': 'two'});
  });

  test('start sends format and preserves native unavailable errors', () async {
    const channel = MethodChannel('recording-format-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if ((call.arguments as Map)['format'] == 'mp3') {
        throw PlatformException(code: 'recording-format-unavailable');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final service = RecordingService(commands: channel);
    await service.start(format: RecordingFormat.m4a);
    await expectLater(
      service.start(format: RecordingFormat.mp3),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'recording-format-unavailable',
        ),
      ),
    );
    expect(calls.map((call) => call.method), ['start', 'start']);
    expect(calls.map((call) => call.arguments), [
      {'format': 'm4a'},
      {'format': 'mp3'},
    ]);
  });
}
