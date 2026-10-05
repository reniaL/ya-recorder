import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../storage/models/recording.dart';

enum PlaybackState { idle, loading, playing, paused, failed }

class PlaybackStatus {
  const PlaybackStatus({
    required this.state,
    this.recordingId,
    this.position = Duration.zero,
    this.errorMessage,
  });

  const PlaybackStatus.idle() : this(state: PlaybackState.idle);

  final PlaybackState state;
  final String? recordingId;
  final Duration position;
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
  Future<void> stop();
  Future<void> dispose();
}

class AudioPlaybackService {
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
    final generation = ++_generation;
    final position = reuse ? previous.position : Duration.zero;

    _setStatus(
      PlaybackStatus(
        state: PlaybackState.loading,
        recordingId: recording.id,
        position: position,
      ),
    );
    return _enqueue(() async {
      if (!_isCurrent(generation)) return;
      try {
        if (!reuse) {
          await _backend.stop();
          if (!_isCurrent(generation)) return;
          await _backend.setFilePath(recording.filePath);
        } else if (previous.state == PlaybackState.idle &&
            position == Duration.zero) {
          await _backend.seek(Duration.zero);
        }
        if (!_isCurrent(generation)) return;
        _setStatus(
          PlaybackStatus(
            state: PlaybackState.playing,
            recordingId: recording.id,
            position: position,
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
          ),
        );
      } catch (error) {
        if (_isCurrent(generation)) _setFailed(_status.recordingId, error);
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

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<void> _enqueue(Future<void> Function() action) {
    return _operations = _operations.then((_) => action());
  }

  void _handleBackendState(AudioBackendState state) {
    final recordingId = _status.recordingId;
    if (recordingId == null ||
        _status.state == PlaybackState.loading ||
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
          ),
        );
      case AudioBackendState.paused:
        _setStatus(
          PlaybackStatus(
            state: PlaybackState.paused,
            recordingId: recordingId,
            position: _status.position,
          ),
        );
      case AudioBackendState.completed:
        _setStatus(
          PlaybackStatus(state: PlaybackState.idle, recordingId: recordingId),
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
        _status.state == PlaybackState.idle) {
      return;
    }
    _setStatus(
      PlaybackStatus(
        state: _status.state,
        recordingId: _status.recordingId,
        position: position,
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
  Future<void> play() => _player.play();

  @override
  Future<void> setFilePath(String filePath) => _player.setFilePath(filePath);

  @override
  Future<void> stop() => _player.stop();
}
