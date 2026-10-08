import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/recording/recording_save_coordinator.dart';
import 'package:ya_recorder/recording/recording_service.dart';
import 'package:ya_recorder/storage/models/recording.dart';
import 'package:ya_recorder/storage/recording_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('save-protocol-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> trace;
  late _Store store;
  late RecordingSaveCoordinator coordinator;
  late bool failAcknowledgement;

  setUp(() {
    trace = [];
    store = _Store(trace);
    failAcknowledgement = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      trace.add('${call.method}:${(call.arguments as Map)['id']}');
      if (call.method == 'acknowledgeRecording' && failAcknowledgement) {
        throw PlatformException(code: 'cleanup-failed');
      }
      return null;
    });
    coordinator = RecordingSaveCoordinator(
      service: RecordingService(commands: channel),
      getStore: () async => store,
      titleFor: (_) => 'default',
    );
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  SavedNativeRecording ready(String id, {String? filePath}) =>
      SavedNativeRecording(
        id: id,
        filePath: filePath ?? '/private/$id.mp3',
        createdAt: DateTime.utc(2026, 10, 8),
        duration: const Duration(seconds: 3),
        fileSizeBytes: 128,
        wasInterrupted: false,
        format: RecordingFormat.mp3,
      );

  test('acknowledges only after a committed index transaction', () async {
    final gate = Completer<void>();
    store.gate = gate.future;
    final pending = coordinator.commit(ready('one'));
    await Future<void>.delayed(Duration.zero);
    expect(trace, ['insert:one']);
    gate.complete();
    final result = await pending;
    expect(result.inserted, isTrue);
    expect(result.acknowledgementPending, isFalse);
    expect(trace, ['insert:one', 'committed:one', 'acknowledgeRecording:one']);
  });

  test('live and recovery duplicates share one in-flight commit', () async {
    final first = coordinator.commit(ready('one'));
    final second = coordinator.commit(ready('one'));
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    expect(store.rows.length, 1);
    expect(trace.where((s) => s.startsWith('insert:')).length, 1);
  });

  test('conflicting replay during a commit is rejected', () async {
    final gate = Completer<void>();
    store.gate = gate.future;
    final first = coordinator.commit(ready('one'));
    await expectLater(
      coordinator.commit(ready('one', filePath: '/other/one.mp3')),
      throwsStateError,
    );
    gate.complete();
    await first;
    expect(store.rows.single.filePath, '/private/one.mp3');
  });

  test(
    'failed index retains native draft, ends wait and permits retry',
    () async {
      store.fail = true;
      await expectLater(coordinator.commit(ready('one')), throwsStateError);
      expect(trace, ['insert:one', 'deferRecording:one']);
      expect(store.rows, isEmpty);
      store.fail = false;
      expect((await coordinator.commit(ready('one'))).inserted, isTrue);
      expect(trace.last, 'acknowledgeRecording:one');
    },
  );

  test(
    'lost acknowledgement replays idempotently without false save failure',
    () async {
      failAcknowledgement = true;
      final first = await coordinator.commit(ready('one'));
      expect(first.inserted, isTrue);
      expect(first.acknowledgementPending, isTrue);
      failAcknowledgement = false;
      final replay = await coordinator.commit(ready('one'));
      expect(replay.inserted, isFalse);
      expect(replay.acknowledgementPending, isFalse);
      expect(store.rows.length, 1);
    },
  );

  test(
    'a failed recording does not poison subsequent serial commits',
    () async {
      store.failId = 'one';
      final first = coordinator.commit(ready('one'));
      final next = coordinator.commit(ready('two'));
      await expectLater(first, throwsStateError);
      expect((await next).inserted, isTrue);
      expect(store.rows.single.id, 'two');
      expect(trace, [
        'insert:one',
        'deferRecording:one',
        'insert:two',
        'committed:two',
        'acknowledgeRecording:two',
      ]);
    },
  );
}

class _Store extends RecordingStore {
  _Store(this.trace)
    : super(databasePath: 'unused', databaseFactory: databaseFactoryFfi);
  final List<String> trace;
  final List<Recording> rows = [];
  Future<void>? gate;
  bool fail = false;
  String? failId;
  @override
  Future<bool> commitNativeRecording(Recording recording) async {
    trace.add('insert:${recording.id}');
    if (gate != null) await gate;
    if (fail || failId == recording.id) throw StateError('index failure');
    if (rows.any((r) => r.id == recording.id)) return false;
    rows.add(recording);
    trace.add('committed:${recording.id}');
    return true;
  }
}
