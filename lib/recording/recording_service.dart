import 'dart:async';

import 'package:flutter/services.dart';

import 'recording_format.dart';

enum RecordingLifecycleState {
  idle,
  preparing,
  recording,
  paused,
  stopping,
  discarding,
  failed,
}

class RecordingSessionStatus {
  const RecordingSessionStatus({
    required this.state,
    required this.elapsed,
    required this.canResume,
    this.sessionId,
    this.format,
  });

  final RecordingLifecycleState state;
  final Duration elapsed;
  final bool canResume;
  final String? sessionId;
  final RecordingFormat? format;

  factory RecordingSessionStatus.fromMap(Map<Object?, Object?> map) {
    final state = _parseState(map['state']);
    final sessionId = map['sessionId'] as String?;
    final needsFormat =
        sessionId != null ||
        (state != RecordingLifecycleState.idle &&
            state != RecordingLifecycleState.failed);
    final format = map['format'] == null && !needsFormat
        ? null
        : RecordingFormat.fromWireValue(map['format']);
    return RecordingSessionStatus(
      state: state,
      elapsed: Duration(milliseconds: _readInt(map, 'elapsedMs')),
      canResume: _readBool(map, 'canResume'),
      sessionId: sessionId,
      format: format,
    );
  }
}

class SavedNativeRecording {
  const SavedNativeRecording({
    required this.id,
    required this.filePath,
    required this.createdAt,
    required this.duration,
    required this.fileSizeBytes,
    required this.wasInterrupted,
    required this.format,
  });

  final String id;
  final String filePath;
  final DateTime createdAt;
  final Duration duration;
  final int fileSizeBytes;
  final bool wasInterrupted;
  final RecordingFormat format;

  factory SavedNativeRecording.fromMap(Map<Object?, Object?> map) {
    final format = RecordingFormat.fromWireValue(map['format']);
    final filePath = _readString(map, 'filePath');
    if (!format.matchesCompletedPath(filePath)) {
      throw const FormatException(
        'Saved path does not match recording format.',
      );
    }
    return SavedNativeRecording(
      id: _readString(map, 'id'),
      filePath: filePath,
      format: format,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        _readInt(map, 'createdAtMs'),
        isUtc: true,
      ),
      duration: Duration(milliseconds: _readInt(map, 'durationMs')),
      fileSizeBytes: _readInt(map, 'fileSizeBytes'),
      wasInterrupted: _readBool(map, 'wasInterrupted'),
    );
  }
}

sealed class RecordingEvent {
  const RecordingEvent();

  factory RecordingEvent.fromMap(Map<Object?, Object?> map) {
    switch (_readString(map, 'type')) {
      case 'state':
        return RecordingStateChanged(RecordingSessionStatus.fromMap(map));
      case 'saved':
        final recording = map['recording'];
        if (recording is! Map) {
          throw const FormatException('Saved event is missing its recording.');
        }
        return RecordingSaved(
          SavedNativeRecording.fromMap(Map<Object?, Object?>.from(recording)),
        );
      case 'error':
        return RecordingFailed(
          code: _readString(map, 'code'),
          message: _readString(map, 'message'),
        );
      default:
        throw FormatException('Unknown recording event: ${map['type']}');
    }
  }
}

class RecordingStateChanged extends RecordingEvent {
  const RecordingStateChanged(this.status);

  final RecordingSessionStatus status;
}

class RecordingSaved extends RecordingEvent {
  const RecordingSaved(this.recording);

  final SavedNativeRecording recording;
}

class RecordingFailed extends RecordingEvent {
  const RecordingFailed({required this.code, required this.message});

  final String code;
  final String message;
}

class RecordingService {
  RecordingService({
    MethodChannel? commands,
    EventChannel? events,
    Stream<RecordingEvent>? eventStream,
  }) : _commands = commands ?? const MethodChannel(_commandChannelName),
       _events = events ?? const EventChannel(_eventChannelName),
       _eventStream = eventStream;

  static const _commandChannelName =
      'io.github.renial.ya_recorder/recording_commands';
  static const _eventChannelName =
      'io.github.renial.ya_recorder/recording_events';

  final MethodChannel _commands;
  final EventChannel _events;
  final Stream<RecordingEvent>? _eventStream;

  Stream<RecordingEvent> get events =>
      _eventStream ??
      _events.receiveBroadcastStream().map((Object? rawEvent) {
        if (rawEvent is! Map) {
          throw const FormatException('Recording event must be a map.');
        }
        return RecordingEvent.fromMap(Map<Object?, Object?>.from(rawEvent));
      });

  Future<bool> requestMicrophonePermission() async {
    return await _commands.invokeMethod<bool>('requestMicrophonePermission') ??
        false;
  }

  Future<void> openAppSettings() => _sendCommand('openAppSettings');

  Future<RecordingSessionStatus> getStatus() async {
    final response = await _commands.invokeMethod<Object?>('getStatus');
    if (response is! Map) {
      throw const FormatException('Recording status must be a map.');
    }
    return RecordingSessionStatus.fromMap(Map<Object?, Object?>.from(response));
  }

  Future<void> start({required RecordingFormat format}) async {
    await _commands.invokeMethod<void>('start', {'format': format.wireName});
  }

  Future<void> pause() => _sendCommand('pause');

  Future<void> resume() => _sendCommand('resume');

  Future<void> stop() => _sendCommand('stop');

  Future<void> cancel() => _sendCommand('cancel');

  Future<void> _sendCommand(String command) async {
    await _commands.invokeMethod<void>(command);
  }
}

RecordingLifecycleState _parseState(Object? value) {
  if (value is! String) {
    throw const FormatException('Recording state must be a string.');
  }

  for (final state in RecordingLifecycleState.values) {
    if (state.name == value) {
      return state;
    }
  }
  throw FormatException('Unknown recording state: $value');
}

int _readInt(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  throw FormatException('$key must be an integer.');
}

bool _readBool(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('$key must be a boolean.');
}

String _readString(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('$key must be a non-empty string.');
}
