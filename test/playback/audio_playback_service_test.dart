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

  test(
    'all supported speeds preserve playback state and audio position',
    () async {
      await service.play(_recording('one'));
      await service.seek(const Duration(milliseconds: 400));
      for (final speed in AudioPlaybackService.supportedSpeeds) {
        await service.setSpeed(speed);
        expect(service.status.speed, speed);
        expect(service.status.state, PlaybackState.playing);
        expect(service.status.position.inMilliseconds, 400);
      }
      expect(backend.speeds, [1, ...AudioPlaybackService.supportedSpeeds]);
      expect(backend.filePaths, ['/private/one.m4a']);
      expect(backend.playCalls, 1);
      await service.pause();
      await service.setSpeed(0.75);
      expect(service.status.state, PlaybackState.paused);
      expect(service.status.position.inMilliseconds, 400);
      expect(backend.playCalls, 1);
    },
  );

  test(
    'same recording retains speed across resume, seek and completion',
    () async {
      final recording = _recording('one');
      await service.play(recording);
      await service.setSpeed(1.5);
      await service.pause();
      await service.play(recording);
      await service.seek(const Duration(milliseconds: 300));
      backend.emitPosition(const Duration(milliseconds: 500));
      backend.emit(AudioBackendState.playing);
      await Future<void>.delayed(Duration.zero);
      expect(service.status.speed, 1.5);
      backend.emit(AudioBackendState.completed);
      await Future<void>.delayed(Duration.zero);
      expect(service.status.speed, 1.5);
      expect(service.status.state, PlaybackState.idle);
      await service.play(recording);
      expect(service.status.speed, 1.5);
      expect(backend.speeds, [1, 1.5]);
    },
  );

  test(
    'new recording and playback after stop apply the default speed',
    () async {
      await service.play(_recording('one'));
      await service.setSpeed(2);
      await service.play(_recording('two'));
      expect(service.status.speed, 1);
      expect(backend.speeds, [1, 2, 1]);
      await service.setSpeed(0.75);
      await service.stop();
      expect(service.status.speed, 1);
      await service.play(_recording('two'));
      expect(backend.speeds.last, 1);
      expect(service.status.speed, 1);
    },
  );

  test(
    'invalid speeds are rejected and idle/loading commands do not reach backend',
    () async {
      for (final speed in [0.0, 3.0, double.nan, double.infinity]) {
        expect(() => service.setSpeed(speed), throwsArgumentError);
      }
      await service.setSpeed(2);
      expect(backend.speeds, isEmpty);
      final gate = Completer<void>();
      backend.loadGate = gate.future;
      final loading = service.play(_recording('one'));
      await Future<void>.delayed(Duration.zero);
      await service.setSpeed(2);
      expect(service.status.speed, 1);
      gate.complete();
      await loading;
      expect(backend.speeds, [1]);
    },
  );

  test(
    'speed error preserves prior speed and playback, retry clears error',
    () async {
      await service.play(_recording('one'));
      await service.setSpeed(1.25);
      await service.seek(const Duration(milliseconds: 250));
      backend.failSpeed = true;
      await service.setSpeed(2);
      expect(service.status.speed, 1.25);
      expect(service.status.state, PlaybackState.playing);
      expect(service.status.position.inMilliseconds, 250);
      expect(service.status.errorMessage, '无法调整播放倍速，请重试。');
      backend.failSpeed = false;
      await service.setSpeed(2);
      expect(service.status.speed, 2);
      expect(service.status.errorMessage, isNull);
    },
  );

  test(
    'late speed completion cannot update stopped or replacement playback',
    () async {
      await service.play(_recording('one'));
      final gate = Completer<void>();
      backend.speedGate = gate.future;
      final changing = service.setSpeed(2);
      await Future<void>.delayed(Duration.zero);
      final stopping = service.stop();
      final replacement = service.play(_recording('two'));
      backend.speedGate = null;
      gate.complete();
      await Future.wait([changing, stopping, replacement]);
      expect(service.status.recordingId, 'two');
      expect(service.status.speed, 1);
      expect(backend.speeds.last, 1);
    },
  );

  test('consecutive speed commands are serialized', () async {
    await service.play(_recording('one'));
    final gate = Completer<void>();
    backend.speedGate = gate.future;
    final first = service.setSpeed(1.25);
    final second = service.setSpeed(2);
    await Future<void>.delayed(Duration.zero);
    expect(backend.speeds, [1, 1.25]);
    backend.speedGate = null;
    gate.complete();
    await Future.wait([first, second]);
    expect(backend.speeds, [1, 1.25, 2]);
    expect(service.status.speed, 2);
  });

  test(
    'failed speed rollback stops playback and exposes a retryable failure',
    () async {
      await service.play(_recording('one'));
      await service.setSpeed(1.25);
      backend.failAllSpeeds = true;
      await service.setSpeed(2);
      expect(backend.speeds, [1, 1.25, 2, 1.25]);
      expect(backend.stopCalls, 2);
      expect(service.status.state, PlaybackState.failed);
      backend.failAllSpeeds = false;
      await service.play(_recording('one'));
      expect(service.status.state, PlaybackState.playing);
      expect(service.status.speed, 1.25);
      expect(backend.speeds.last, 1.25);
    },
  );

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

  test(
    'explicit play preserves playing position and resumes without reload',
    () async {
      final recording = _recording('one');
      await service.play(recording);
      await service.seek(const Duration(milliseconds: 400));
      await service.play(recording);
      expect(backend.playCalls, 1);
      expect(service.status.position.inMilliseconds, 400);
      await service.pause();
      await service.play(recording);
      expect(service.status.state, PlaybackState.playing);
      expect(service.status.position.inMilliseconds, 400);
      expect(backend.filePaths, [recording.filePath]);
      expect(backend.playCalls, 2);
    },
  );

  test('completed recording replays from the actual backend start', () async {
    final recording = _recording('one');
    await service.play(recording);
    backend.emit(AudioBackendState.completed);
    await Future<void>.delayed(Duration.zero);
    backend.emitPosition(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(service.status.position, Duration.zero);
    await service.play(recording);
    expect(backend.seekPositions, [Duration.zero]);
    expect(backend.playCalls, 2);
  });

  test('stop invalidates an in-flight file load before it can play', () async {
    final gate = Completer<void>();
    backend.loadGate = gate.future;
    final loading = service.play(_recording('one'));
    await Future<void>.delayed(Duration.zero);
    expect(service.status.state, PlaybackState.loading);
    final stopping = service.stop();
    expect(service.status.recordingId, isNull);
    gate.complete();
    await Future.wait([loading, stopping]);
    expect(backend.playCalls, 0);
    expect(service.status.recordingId, isNull);
  });

  test(
    'manual seek after completion is preserved when playback resumes',
    () async {
      final recording = _recording('one');
      await service.play(recording);
      backend.emit(AudioBackendState.completed);
      await Future<void>.delayed(Duration.zero);
      await service.seek(const Duration(milliseconds: 500));
      await service.play(recording);
      expect(service.status.position.inMilliseconds, 500);
      expect(backend.seekPositions, [const Duration(milliseconds: 500)]);
    },
  );

  test('a new recording cannot race the cancelled previous load', () async {
    final gate = Completer<void>();
    backend.loadGate = gate.future;
    final first = service.play(_recording('one'));
    await Future<void>.delayed(Duration.zero);
    final second = service.play(_recording('two'));
    expect(service.status.recordingId, 'two');
    gate.complete();
    await Future.wait([first, second]);
    expect(backend.filePaths, ['/private/one.m4a', '/private/two.m4a']);
    expect(backend.playCalls, 1);
    expect(service.status.recordingId, 'two');
    expect(service.status.state, PlaybackState.playing);
  });

  test('failed autoplay retries by loading the file again', () async {
    backend.failLoad = true;
    await service.play(_recording('one'));
    expect(service.status.state, PlaybackState.failed);
    expect(backend.playCalls, 0);
    backend.failLoad = false;
    await service.play(_recording('one'));
    expect(service.status.state, PlaybackState.playing);
    expect(backend.filePaths.length, 2);
  });

  test(
    'late errors from cancelled play cannot affect another recording',
    () async {
      final gate = Completer<void>();
      backend.playGate = gate.future;
      await service.play(_recording('one'));
      backend.playGate = null;
      await service.play(_recording('two'));
      gate.completeError(StateError('old playback failed'));
      await Future<void>.delayed(Duration.zero);
      expect(service.status.recordingId, 'two');
      expect(service.status.state, PlaybackState.playing);
    },
  );
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
  final List<double> speeds = [];
  bool failSpeed = false;
  bool failAllSpeeds = false;
  Future<void>? speedGate;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  Future<void>? loadGate;
  Future<void>? playGate;
  bool failLoad = false;

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
    if (playGate != null) await playGate;
  }

  @override
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
  }

  @override
  Future<void> setSpeed(double speed) async {
    speeds.add(speed);
    if (speedGate != null) await speedGate;
    if (failSpeed || failAllSpeeds) {
      failSpeed = false;
      throw StateError('Cannot set speed');
    }
  }

  @override
  Future<void> setFilePath(String filePath) async {
    filePaths.add(filePath);
    if (loadGate != null) await loadGate;
    if (failLoad) throw StateError('Cannot load audio');
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }
}
