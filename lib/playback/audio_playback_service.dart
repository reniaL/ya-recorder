import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../storage/models/recording.dart';

enum PlaybackState { idle, loading, playing, paused, failed }

class PlaybackStatus {
  const PlaybackStatus({
    required this.state,
    this.recordingId,
    this.position = Duration.zero,
    this.speed = 1,
    this.errorMessage,
  });

  const PlaybackStatus.idle() : this(state: PlaybackState.idle);

  final PlaybackState state;
  final String? recordingId;
  final Duration position;
  final double speed;
  final String? errorMessage;
}

enum AudioBackendState { idle, playing, paused, completed }

abstract interface class AudioPlaybackBackend {
  Stream<AudioBackendState> get states;
  Stream<Duration> get positions;

  Future<void> setFilePath(String filePath);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> stop();
  Future<void> dispose();
}

class AudioPlaybackService {
  static const supportedSpeeds = <double>[0.75, 1, 1.25, 1.5, 2];

  AudioPlaybackService({AudioPlaybackBackend? backend})
    : _backend = backend ?? JustAudioPlaybackBackend() {
    _backendSubscription = _backend.states.listen(
      _handleBackendState,
      onError: _handleBackendError,
    );
    _positionSubscription = _backend.positions.listen(
      _handlePosition,
      onError: _handleBackendError,
    );
  }

  final AudioPlaybackBackend _backend;
  final StreamController<PlaybackStatus> _statusController =
      StreamController<PlaybackStatus>.broadcast();
  late final StreamSubscription<AudioBackendState> _backendSubscription;
  late final StreamSubscription<Duration> _positionSubscription;

  PlaybackStatus _status = const PlaybackStatus.idle();
  Future<void> _operations = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  bool _isSkipping = false;
  Duration _duration = Duration.zero;

  PlaybackStatus get status => _status;
  Stream<PlaybackStatus> get statuses => _statusController.stream;

  Future<void> toggle(Recording recording) async {
    if (_status.recordingId == recording.id) {
      if (_status.state == PlaybackState.playing) {
        await pause();
        return;
      }
      if (_status.state == PlaybackState.loading) {
        return;
      }
      await play(recording);
      return;
    }

    await play(recording);
  }

  /// Starts or resumes without toggling an already playing recording off.
  Future<void> play(Recording recording) {
    if (_disposed) return Future<void>.value();
    final previous = _status;
    final sameRecording = previous.recordingId == recording.id;
    if (sameRecording && previous.state == PlaybackState.playing) {
      return Future<void>.value();
    }
    if (sameRecording && previous.state == PlaybackState.loading) {
      return _operations;
    }
    final reuse = sameRecording && previous.state != PlaybackState.failed;
    _duration = recording.duration;
    final atEnd = _duration > Duration.zero && previous.position >= _duration;
    final generation = ++_generation;
    final position = reuse && !atEnd ? previous.position : Duration.zero;
    final speed = sameRecording ? previous.speed : 1.0;

    _setStatus(
      PlaybackStatus(
        state: PlaybackState.loading,
        recordingId: recording.id,
        position: position,
        speed: speed,
      ),
    );
    return _enqueue(() async {
      if (!_isCurrent(generation)) return;
      try {
        if (!reuse) {
          await _backend.stop();
          if (!_isCurrent(generation)) return;
          await _backend.setFilePath(recording.filePath);
          if (!_isCurrent(generation)) return;
          await _backend.setSpeed(speed);
        } else if (atEnd ||
            (previous.state == PlaybackState.idle &&
                position == Duration.zero)) {
          await _backend.seek(Duration.zero);
        }
        if (!_isCurrent(generation)) return;
        _setStatus(
          PlaybackStatus(
            state: PlaybackState.playing,
            recordingId: recording.id,
            position: position,
            speed: speed,
          ),
        );
        unawaited(
          _backend.play().catchError((Object error) {
            if (_isCurrent(generation)) _setFailed(recording.id, error);
          }),
        );
      } catch (error) {
        if (_isCurrent(generation)) _setFailed(recording.id, error);
      }
    });
  }

  Future<void> pause() async {
    if (_status.state != PlaybackState.playing) {
      return;
    }
    final generation = _generation;
    await _enqueue(() async {
      if (!_isCurrent(generation)) return;
      try {
        await _backend.pause();
        if (!_isCurrent(generation)) return;
        _setStatus(
          PlaybackStatus(
            state: PlaybackState.paused,
            recordingId: _status.recordingId,
            position: _status.position,
            speed: _status.speed,
          ),
        );
      } catch (error) {
        if (_isCurrent(generation)) _setFailed(_status.recordingId, error);
      }
    });
  }

  Future<void> stop() {
    if (_disposed) return Future<void>.value();
    final generation = ++_generation;
    // Invalidate loading work immediately; stopping the backend is serialized
    // after any pending load so that it cannot later start playing again.
    _setStatus(const PlaybackStatus.idle());
    return _enqueue(() async {
      if (_disposed) return;
      try {
        await _backend.stop();
      } catch (error) {
        if (_isCurrent(generation)) _setFailed(null, error);
      }
    });
  }

  Future<void> seek(Duration position) async {
    if (_status.recordingId == null ||
        position.isNegative ||
        _status.state == PlaybackState.loading ||
        _disposed) {
      return;
    }
    final generation = _generation;
    await _enqueue(() async {
      if (!_isCurrent(generation)) return;
      try {
        await _backend.seek(position);
        if (!_isCurrent(generation)) return;
        _setStatus(
          PlaybackStatus(
            state: _status.state,
            recordingId: _status.recordingId,
            position: position,
            speed: _status.speed,
          ),
        );
      } catch (error) {
        if (_isCurrent(generation)) _setFailed(_status.recordingId, error);
      }
    });
  }

  Future<void> skipForward() => _skip(const Duration(seconds: 5));

  Future<void> skipBackward() => _skip(const Duration(seconds: -5));

  Future<void> _skip(Duration offset) {
    if (_disposed ||
        _status.recordingId == null ||
        _status.state == PlaybackState.loading ||
        _status.state == PlaybackState.failed ||
        _duration <= Duration.zero) {
      return Future<void>.value();
    }
    final generation = _generation;
    return _enqueue(() async {
      if (!_isCurrent(generation) || _status.state == PlaybackState.failed) {
        return;
      }
      // Compute from the latest position when this command executes so rapid
      // taps accumulate rather than all seeking from the same old position.
      final previous = _status;
      final target = Duration(
        microseconds: (previous.position + offset).inMicroseconds.clamp(
          0,
          _duration.inMicroseconds,
        ),
      );
      final ended =
          previous.state == PlaybackState.playing && target >= _duration;
      _isSkipping = true;
      try {
        if (ended) {
          await _backend.pause();
          if (!_isCurrent(generation)) return;
        }
        await _backend.seek(ended ? Duration.zero : target);
        if (!_isCurrent(generation) || _status.state == PlaybackState.failed) {
          return;
        }
        _setStatus(
          PlaybackStatus(
            state: ended ? PlaybackState.idle : previous.state,
            recordingId: previous.recordingId,
            position: ended ? Duration.zero : target,
            speed: previous.speed,
          ),
        );
      } catch (error) {
        if (!_isCurrent(generation)) return;
        try {
          await _backend.stop();
        } catch (_) {
          // Preserve the original seek failure for the retry UI.
        }
        if (_isCurrent(generation)) _setFailed(previous.recordingId, error);
      } finally {
        _isSkipping = false;
      }
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    ++_generation;
    await _backendSubscription.cancel();
    await _positionSubscription.cancel();
    await _backend.dispose();
    await _statusController.close();
  }

  Future<void> setSpeed(double speed) {
    if (!supportedSpeeds.contains(speed)) {
      throw ArgumentError.value(speed, 'speed', 'Unsupported playback speed');
    }
    if (_disposed ||
        _status.recordingId == null ||
        _status.state == PlaybackState.loading ||
        _status.state == PlaybackState.failed) {
      return Future<void>.value();
    }
    final generation = _generation;
    return _enqueue(() async {
      if (!_isCurrent(generation)) return;
      String? errorMessage;
      var appliedSpeed = _status.speed;
      try {
        await _backend.setSpeed(speed);
        appliedSpeed = speed;
      } catch (_) {
        if (!_isCurrent(generation)) return;
        // The plugin updates its local speed before the platform responds.
        // Restore the last successful value if the native command fails.
        try {
          await _backend.setSpeed(appliedSpeed);
        } catch (error) {
          if (!_isCurrent(generation)) return;
          try {
            await _backend.stop();
          } catch (_) {
            // Keep the failure visible even when the backend cannot stop.
          }
          if (_isCurrent(generation)) _setFailed(_status.recordingId, error);
          return;
        }
        errorMessage = '无法调整播放倍速，请重试。';
      }
      if (!_isCurrent(generation)) return;
      _setStatus(
        PlaybackStatus(
          state: _status.state,
          recordingId: _status.recordingId,
          position: _status.position,
          speed: appliedSpeed,
          errorMessage: errorMessage,
        ),
      );
    });
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<void> _enqueue(Future<void> Function() action) {
    return _operations = _operations.then((_) => action());
  }

  void _handleBackendState(AudioBackendState state) {
    final recordingId = _status.recordingId;
    if (recordingId == null ||
        _status.state == PlaybackState.loading ||
        _status.state == PlaybackState.idle ||
        _isSkipping ||
        _disposed) {
      return;
    }
    switch (state) {
      case AudioBackendState.idle:
        return;
      case AudioBackendState.playing:
        _setStatus(
          PlaybackStatus(
            state: PlaybackState.playing,
            recordingId: recordingId,
            position: _status.position,
            speed: _status.speed,
          ),
        );
      case AudioBackendState.paused:
        _setStatus(
          PlaybackStatus(
            state: PlaybackState.paused,
            recordingId: recordingId,
            position: _status.position,
            speed: _status.speed,
          ),
        );
      case AudioBackendState.completed:
        if (_status.state == PlaybackState.paused) return;
        _setStatus(
          PlaybackStatus(
            state: PlaybackState.idle,
            recordingId: recordingId,
            speed: _status.speed,
          ),
        );
    }
  }

  void _handleBackendError(Object error, [StackTrace? stackTrace]) {
    if (_disposed || _status.recordingId == null) return;
    _setFailed(_status.recordingId, error);
  }

  void _handlePosition(Duration position) {
    if (_status.recordingId == null ||
        position.isNegative ||
        _disposed ||
        _status.state == PlaybackState.loading ||
        _isSkipping ||
        _status.state == PlaybackState.idle) {
      return;
    }
    _setStatus(
      PlaybackStatus(
        state: _status.state,
        recordingId: _status.recordingId,
        position: position,
        speed: _status.speed,
        errorMessage: _status.errorMessage,
      ),
    );
  }

  void _setFailed(String? recordingId, Object error) {
    _setStatus(
      PlaybackStatus(
        state: PlaybackState.failed,
        recordingId: recordingId,
        position: _status.position,
        speed: _status.speed,
        errorMessage: '无法播放该录音。',
      ),
    );
  }

  void _setStatus(PlaybackStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }
}

class JustAudioPlaybackBackend implements AudioPlaybackBackend {
  JustAudioPlaybackBackend({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<AudioBackendState> get states =>
      _player.playerStateStream.map((state) {
        if (state.processingState == ProcessingState.completed) {
          return AudioBackendState.completed;
        }
        if (state.playing) {
          return AudioBackendState.playing;
        }
        if (state.processingState == ProcessingState.idle) {
          return AudioBackendState.idle;
        }
        return AudioBackendState.paused;
      });

  @override
  Stream<Duration> get positions => _player.positionStream;

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> setFilePath(String filePath) => _player.setFilePath(filePath);

  @override
  Future<void> stop() => _player.stop();
}
