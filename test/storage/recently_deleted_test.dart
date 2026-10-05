import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/storage/models/recording.dart';
import 'package:ya_recorder/storage/recording_store.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late RecordingStore store;
  final now = DateTime.utc(2026, 10, 5, 12);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ya-trash-');
    store = RecordingStore(
      databasePath: path.join(directory.path, 'index.db'),
      databaseFactory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<File> save(String id, {DateTime? deletedAt, String? folderId}) async {
    final file = File(path.join(directory.path, '$id.m4a'));
    await file.writeAsBytes([1, 2, 3]);
    await store.saveRecording(
      Recording(
        id: id,
        title: id,
        filePath: file.path,
        createdAt: now,
        duration: const Duration(seconds: 12),
        fileSizeBytes: 3,
        folderId: folderId,
        wasInterrupted: true,
      ),
    );
    if (deletedAt != null) {
      await store.softDeleteRecording(recordingId: id, deletedAt: deletedAt);
    }
    return file;
  }

  test(
    'restore preserves file and metadata, falls back after folder deletion',
    () async {
      await store.createFolder(id: 'work', name: 'Work');
      final file = await save('one', deletedAt: now, folderId: 'work');
      await store.restoreRecording('one', now: now);
      final restored = (await store.listRecordings(folderId: 'work')).single;
      expect(restored.title, 'one');
      expect(restored.createdAt, now);
      expect(restored.filePath, file.path);
      expect(restored.duration, const Duration(seconds: 12));
      expect(restored.fileSizeBytes, 3);
      expect(restored.wasInterrupted, isTrue);
      expect(await file.readAsBytes(), [1, 2, 3]);
      await store.softDeleteRecording(recordingId: 'one', deletedAt: now);
      await store.deleteFolder(folderId: 'work');
      await store.restoreRecording('one', now: now);
      await store.close();
      await store.open();
      expect((await store.listRecordings()).single.folderId, isNull);
      expect(await store.listRecentlyDeleted(), isEmpty);
      expect(await file.readAsBytes(), [1, 2, 3]);
    },
  );

  test(
    'permanent deletion removes file and index, protects active recordings',
    () async {
      final active = await save('active');
      await expectLater(
        store.permanentlyDeleteRecording('active'),
        throwsStateError,
      );
      expect(await active.exists(), isTrue);
      final deleted = await save('deleted', deletedAt: now);
      await store.permanentlyDeleteRecording('deleted');
      expect(await deleted.exists(), isFalse);
      expect(await store.listRecentlyDeleted(), isEmpty);
      final missing = await save('missing', deletedAt: now);
      await missing.delete();
      await expectLater(
        store.restoreRecording('missing', now: now),
        throwsStateError,
      );
      expect((await store.listRecentlyDeleted()).single.id, 'missing');
      await store.permanentlyDeleteRecording('missing');
      await store.close();
      await store.open();
      expect(await store.listRecentlyDeleted(), isEmpty);
      expect((await store.listRecordings()).single.id, 'active');
    },
  );

  test(
    '30 day boundary uses deletion time and expired restore is rejected',
    () async {
      final expired = await save(
        'expired',
        deletedAt: now.subtract(const Duration(days: 30)),
      );
      final retained = await save(
        'retained',
        deletedAt: now
            .subtract(const Duration(days: 30))
            .add(const Duration(milliseconds: 1)),
      );
      final active = await save('active');
      await expectLater(
        store.restoreRecording('expired', now: now),
        throwsStateError,
      );
      expect(await store.purgeExpiredRecordings(now: now), isEmpty);
      expect(await expired.exists(), isFalse);
      expect(await retained.exists(), isTrue);
      expect(await active.exists(), isTrue);
      expect((await store.listRecentlyDeleted()).single.id, 'retained');
      await store.restoreRecording('retained', now: now);
    },
  );

  test(
    'file deletion failure keeps index, continues cleanup and retries after restart',
    () async {
      final failed = await save(
        'failed',
        deletedAt: now.subtract(const Duration(days: 31)),
      );
      final good = await save(
        'good',
        deletedAt: now.subtract(const Duration(days: 31)),
      );
      await store.close();
      store = RecordingStore(
        databasePath: path.join(directory.path, 'index.db'),
        databaseFactory: databaseFactoryFfi,
        deleteAudioFile: (filePath) async {
          if (filePath == failed.path) {
            throw const FileSystemException('Access denied');
          }
          await File(filePath).delete();
        },
      );
      await expectLater(
        store.permanentlyDeleteRecording('failed'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await store.purgeExpiredRecordings(now: now), ['failed']);
      expect(await failed.readAsBytes(), [1, 2, 3]);
      expect(await good.exists(), isFalse);
      expect((await store.listRecentlyDeleted()).single.id, 'failed');
      await store.close();
      store = RecordingStore(
        databasePath: path.join(directory.path, 'index.db'),
        databaseFactory: databaseFactoryFfi,
      );
      expect(await store.purgeExpiredRecordings(now: now), isEmpty);
      expect(await failed.exists(), isFalse);
      expect(await store.listRecentlyDeleted(), isEmpty);
    },
  );
}
