import 'package:flutter_test/flutter_test.dart';
import 'package:ya_recorder/recording/recording_service.dart';

void main() {
  test('parses a native recording state event', () {
    final event = RecordingEvent.fromMap({
      'type': 'state',
      'state': 'paused',
      'elapsedMs': 1250,
      'canResume': true,
      'sessionId': 'session-1',
    });

    expect(event, isA<RecordingStateChanged>());
    final stateChanged = event as RecordingStateChanged;
    expect(stateChanged.status.state, RecordingLifecycleState.paused);
    expect(stateChanged.status.elapsed, const Duration(milliseconds: 1250));
    expect(stateChanged.status.canResume, isTrue);
    expect(stateChanged.status.sessionId, 'session-1');
  });

  test('parses a saved recording result', () {
    final event = RecordingEvent.fromMap({
      'type': 'saved',
      'recording': {
        'id': 'session-1',
        'filePath': '/data/recording-session-1.m4a',
        'createdAtMs': 1727568000000,
        'durationMs': 3000,
        'fileSizeBytes': 4096,
        'wasInterrupted': false,
      },
    });

    expect(event, isA<RecordingSaved>());
    final saved = event as RecordingSaved;
    expect(saved.recording.id, 'session-1');
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
}
