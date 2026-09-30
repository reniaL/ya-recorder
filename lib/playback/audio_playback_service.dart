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
      await _resume();
      return;
    }

    _setStatus(
      PlaybackStatus(state: PlaybackState.loading, recordingId: recording.id),
    );
    try {
      await _backend.stop();
      await _backend.setFilePath(recording.filePath);
      _setStatus(
        PlaybackStatus(state: PlaybackState.playing, recordingId: recording.id),
      );
      unawaited(_backend.play().catchError(_handleBackendError));
    } catch (error) {
      _setFailed(recording.id, error);
    }
  }

  Future<void> pause() async {
    if (_status.state != PlaybackState.playing) {
      return;
    }
    try {
      await _backend.pause();
      _setStatus(
        PlaybackStatus(
          state: PlaybackState.paused,
          recordingId: _status.recordingId,
          position: _status.position,
        ),
      );
    } catch (error) {
      _setFailed(_status.recordingId, error);
    }
  }

  Future<void> stop() async {
    try {
      await _backend.stop();
      _setStatus(const PlaybackStatus.idle());
    } catch (error) {
      _setFailed(_status.recordingId, error);
    }
  }

  Future<void> seek(Duration position) async {
    if (_status.recordingId == null || position.isNegative) {
      return;
    }
    try {
      await _backend.seek(position);
      _setStatus(
        PlaybackStatus(
          state: _status.state,
          recordingId: _status.recordingId,
          position: position,
        ),
      );
    } catch (error) {
      _setFailed(_status.recordingId, error);
    }
  }

  Future<void> dispose() async {
    await _backendSubscription.cancel();
    await _positionSubscription.cancel();
    await _backend.dispose();
    await _statusController.close();
  }

  Future<void> _resume() async {
    try {
      _setStatus(
        PlaybackStatus(
          state: PlaybackState.playing,
          recordingId: _status.recordingId,
          position: _status.position,
        ),
      );
      unawaited(_backend.play().catchError(_handleBackendError));
    } catch (error) {
      _setFailed(_status.recordingId, error);
    }
  }

  void _handleBackendState(AudioBackendState state) {
    final recordingId = _status.recordingId;
    if (recordingId == null) {
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
    _setFailed(_status.recordingId, error);
  }

  void _handlePosition(Duration position) {
    if (_status.recordingId == null || position.isNegative) {
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
