import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ya_recorder/playback/audio_playback_service.dart';
import 'package:ya_recorder/storage/models/recording.dart';

void main() {
  late _FakeAudioPlaybackBackend backend;
  late AudioPlaybackService service;

  setUp(() {
    backend = _FakeAudioPlaybackBackend();
    service = AudioPlaybackService(backend: backend);
  });

  tearDown(() async {
    await service.dispose();
  });

  test('plays, pauses, and replaces the active recording', () async {
    final first = _recording('recording-1');
    final second = _recording('recording-2');

    await service.toggle(first);
    expect(service.status.state, PlaybackState.playing);
    expect(service.status.recordingId, first.id);
    expect(backend.filePaths, [first.filePath]);
    expect(backend.playCalls, 1);

    await service.toggle(first);
    expect(service.status.state, PlaybackState.paused);
    expect(backend.pauseCalls, 1);

    await service.toggle(second);
    expect(service.status.state, PlaybackState.playing);
    expect(service.status.recordingId, second.id);
    expect(backend.filePaths, [first.filePath, second.filePath]);
    expect(backend.stopCalls, 2);
    expect(backend.playCalls, 2);
  });

  test(
    'returns the active recording to an idle state after completion',
    () async {
      final recording = _recording('recording-1');
      await service.toggle(recording);

      backend.emit(AudioBackendState.completed);
      await Future<void>.delayed(Duration.zero);

      expect(service.status.state, PlaybackState.idle);
      expect(service.status.recordingId, recording.id);
    },
  );

  test('publishes playback position and seeks the active recording', () async {
    final recording = _recording('recording-1');
    await service.toggle(recording);

    backend.emitPosition(const Duration(milliseconds: 750));
    await Future<void>.delayed(Duration.zero);

    expect(service.status.position, const Duration(milliseconds: 750));

    await service.seek(const Duration(milliseconds: 250));

    expect(backend.seekPositions, [const Duration(milliseconds: 250)]);
    expect(service.status.position, const Duration(milliseconds: 250));
  });
}

Recording _recording(String id) {
  return Recording(
    id: id,
    title: id,
    filePath: '/private/$id.m4a',
    createdAt: DateTime.utc(2026, 9, 30),
    duration: const Duration(seconds: 1),
    fileSizeBytes: 1,
  );
}

class _FakeAudioPlaybackBackend implements AudioPlaybackBackend {
  final StreamController<AudioBackendState> _stateController =
      StreamController<AudioBackendState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final List<String> filePaths = [];
  final List<Duration> seekPositions = [];
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;

  @override
  Stream<AudioBackendState> get states => _stateController.stream;

  @override
  Stream<Duration> get positions => _positionController.stream;

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
  }

  void emit(AudioBackendState state) => _stateController.add(state);

  void emitPosition(Duration position) => _positionController.add(position);

  @override
  Future<void> pause() async {
    pauseCalls += 1;
  }

  @override
  Future<void> play() async {
    playCalls += 1;
  }

  @override
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
  }

  @override
  Future<void> setFilePath(String filePath) async {
    filePaths.add(filePath);
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }
}
