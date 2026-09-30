import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../storage/models/recording.dart';

enum PlaybackState { idle, loading, playing, paused, failed }

class PlaybackStatus {
  const PlaybackStatus({
    required this.state,
    this.recordingId,
    this.errorMessage,
  });

  const PlaybackStatus.idle() : this(state: PlaybackState.idle);

  final PlaybackState state;
  final String? recordingId;
  final String? errorMessage;
}

enum AudioBackendState { idle, playing, paused, completed }

abstract interface class AudioPlaybackBackend {
  Stream<AudioBackendState> get states;

  Future<void> setFilePath(String filePath);
  Future<void> play();
  Future<void> pause();
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
  }

  final AudioPlaybackBackend _backend;
  final StreamController<PlaybackStatus> _statusController =
      StreamController<PlaybackStatus>.broadcast();
  late final StreamSubscription<AudioBackendState> _backendSubscription;

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

  Future<void> dispose() async {
    await _backendSubscription.cancel();
    await _backend.dispose();
    await _statusController.close();
  }

  Future<void> _resume() async {
    try {
      _setStatus(
        PlaybackStatus(
          state: PlaybackState.playing,
          recordingId: _status.recordingId,
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
          ),
        );
      case AudioBackendState.paused:
        _setStatus(
          PlaybackStatus(state: PlaybackState.paused, recordingId: recordingId),
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

  void _setFailed(String? recordingId, Object error) {
    _setStatus(
      PlaybackStatus(
        state: PlaybackState.failed,
        recordingId: recordingId,
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
  Future<void> dispose() => _player.dispose();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> setFilePath(String filePath) => _player.setFilePath(filePath);

  @override
  Future<void> stop() => _player.stop();
}
