import '../storage/models/recording.dart';
import '../storage/recording_store.dart';
import 'recording_service.dart';

class RecordingCommitResult {
  const RecordingCommitResult({
    required this.inserted,
    required this.acknowledgementPending,
  });

  final bool inserted;
  final bool acknowledgementPending;
}

/// Serializes live events and startup replays. SQLite commits before the native
/// journal acknowledgement; a lost acknowledgement remains safe to replay.
class RecordingSaveCoordinator {
  RecordingSaveCoordinator({
    required this.service,
    required this.getStore,
    required this.titleFor,
  });

  final RecordingService service;
  final Future<RecordingStore> Function() getStore;
  final String Function(DateTime) titleFor;
  Future<void> _tail = Future.value();
  final Map<String, Future<RecordingCommitResult>> _inFlight = {};
  final Map<String, SavedNativeRecording> _candidates = {};

  Future<RecordingCommitResult> commit(SavedNativeRecording ready) {
    final existing = _inFlight[ready.id];
    if (existing != null) {
      final prior = _candidates[ready.id]!;
      if (prior.filePath != ready.filePath ||
          prior.format != ready.format ||
          prior.createdAt != ready.createdAt ||
          prior.duration != ready.duration ||
          prior.fileSizeBytes != ready.fileSizeBytes ||
          prior.wasInterrupted != ready.wasInterrupted) {
        return Future.error(StateError('Conflicting recording replay.'));
      }
      return existing;
    }
    final operation = _tail.then((_) => _commit(ready));
    _inFlight[ready.id] = operation;
    _candidates[ready.id] = ready;
    _tail = operation.then<void>(
      (_) {
        _inFlight.remove(ready.id);
        _candidates.remove(ready.id);
      },
      onError: (Object error, StackTrace stack) {
        _inFlight.remove(ready.id);
        _candidates.remove(ready.id);
      },
    );
    return operation;
  }

  Future<RecordingCommitResult> _commit(SavedNativeRecording ready) async {
    bool inserted;
    try {
      final store = await getStore();
      inserted = await store.commitNativeRecording(
        Recording(
          id: ready.id,
          title: titleFor(ready.createdAt),
          filePath: ready.filePath,
          createdAt: ready.createdAt,
          duration: ready.duration,
          fileSizeBytes: ready.fileSizeBytes,
          format: ready.format,
          wasInterrupted: ready.wasInterrupted,
        ),
      );
    } catch (_) {
      // Keep the durable READY draft, while ending the foreground wait.
      try {
        await service.deferRecording(ready.id);
      } catch (_) {
        // Recovery remains possible even if the bridge itself was lost.
      }
      rethrow;
    }
    try {
      await service.acknowledgeRecording(ready.id);
      return RecordingCommitResult(
        inserted: inserted,
        acknowledgementPending: false,
      );
    } catch (_) {
      return RecordingCommitResult(
        inserted: inserted,
        acknowledgementPending: true,
      );
    }
  }
}
