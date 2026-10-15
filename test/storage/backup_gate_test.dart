import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/backup/backup_progress.dart';
import 'package:ya_recorder/backup/library_coordinator.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/settings/app_language.dart';
import 'package:ya_recorder/storage/models/recording.dart';
import 'package:ya_recorder/storage/recording_store.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late RecordingStore store;
  final now = DateTime.utc(2026, 10, 15);
  Future<void> tick() => Future<void>.delayed(Duration.zero);

  Recording recording(String id) => Recording(
    id: id,
    title: id,
    filePath: '${directory.path}/$id.aac',
    createdAt: now,
    duration: const Duration(seconds: 1),
    fileSizeBytes: 3,
    format: RecordingFormat.aac,
    folderId: 'folder-old',
  );

  Future<T> backup<T>(Future<T> Function(BackupLease) action) =>
      store.coordinator.runBackup(
        taskId: 'test',
        operation: BackupOperation.export,
        recordingIsIdle: () async => true,
        action: action,
      );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('backup-gate-');
    store = RecordingStore(
      databasePath: '${directory.path}/index.db',
      databaseFactory: databaseFactoryFfi,
    );
    await store.createFolder(id: 'folder-old', name: 'Old');
    await store.createFolder(id: 'folder-empty', name: 'Empty');
    for (final id in ['active', 'deleted', 'expired']) {
      await File(recording(id).filePath).writeAsBytes([1, 2, 3]);
      await store.saveRecording(recording(id));
    }
    await store.softDeleteRecording(recordingId: 'deleted', deletedAt: now);
    await store.softDeleteRecording(
      recordingId: 'expired',
      deletedAt: now.subtract(const Duration(days: 31)),
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('injected startup recovery finishes before a store may write', () async {
    final recovered = Completer<void>();
    final gate = LibraryCoordinator(
      recoverInterruptedTask: () => recovered.future,
    );
    final isolated = RecordingStore(
      databasePath: '${directory.path}/startup.db',
      databaseFactory: databaseFactoryFfi,
      libraryCoordinator: gate,
    );
    var created = false;
    final write = isolated.createFolder(id: 'new', name: 'New').then((_) {
      created = true;
    });
    await tick();
    expect(created, isFalse);
    recovered.complete();
    await write;
    expect((await isolated.listFolders()).single.id, 'new');
    final mismatch = RecordingStore(
      databasePath: isolated.databasePath,
      databaseFactory: databaseFactoryFfi,
      libraryCoordinator: LibraryCoordinator(),
    );
    expect(() => mismatch.coordinator, throwsStateError);
    await isolated.close();
  });

  test(
    'every ordinary write blocked while snapshot reads and preferences remain available',
    () async {
      final before = (await store.listRecordings()).single.toDatabaseMap();
      await backup((lease) async {
        final writes = <Future<dynamic> Function()>[
          () => store.createFolder(id: 'new', name: 'New'),
          () => store.reorderFolders(['folder-empty', 'folder-old']),
          () => store.renameFolder(folderId: 'folder-old', name: 'Changed'),
          () => store.deleteFolder(folderId: 'folder-empty'),
          () => store.saveRecording(recording('new')),
          () => store.commitNativeRecording(recording('native')),
          () => store.moveRecording(
            recordingId: 'active',
            folderId: 'folder-empty',
          ),
          () => store.renameRecording(recordingId: 'active', title: 'Changed'),
          () => store.moveRecordings(recordingIds: ['active']),
          () => store.softDeleteRecordings(
            recordingIds: ['active'],
            deletedAt: now,
          ),
          () =>
              store.softDeleteRecording(recordingId: 'active', deletedAt: now),
          () => store.restoreRecording('deleted', now: now),
          () => store.permanentlyDeleteRecording('deleted'),
        ];
        for (final write in writes) {
          await expectLater(write(), throwsA(isA<LibraryBusyException>()));
        }
        final snapshot = await store.snapshotForBackup(lease);
        expect(snapshot.recordings.map((r) => r.id), ['active']);
        expect(snapshot.folders.map((f) => f.id), [
          'folder-old',
          'folder-empty',
        ]);
        expect(snapshot.allRecordingIds, {'active', 'deleted', 'expired'});
        expect(() => snapshot.allRecordingIds.clear(), throwsUnsupportedError);
        expect((await store.listRecordings()).single.toDatabaseMap(), before);
        await store.setThemeMode(ThemeMode.dark);
        await store.setAppLanguage(AppLanguage.english);
        await store.setDefaultRecordingFormat(RecordingFormat.mp3);
        expect(await store.getThemeMode(), ThemeMode.dark);
        expect(await store.getAppLanguage(), AppLanguage.english);
        expect(await File(recording('active').filePath).readAsBytes(), [
          1,
          2,
          3,
        ]);
      });
      await store.renameRecording(recordingId: 'active', title: 'After');
      expect((await store.listRecordings()).single.title, 'After');
    },
  );

  test(
    'shared database handles cannot bypass gate; foreign and expired tokens rejected',
    () async {
      final other = RecordingStore(
        databasePath: store.databasePath,
        databaseFactory: databaseFactoryFfi,
      );
      late BackupLease expired;
      await backup((lease) async {
        expired = lease;
        expect(identical(other.coordinator, store.coordinator), isTrue);
        await expectLater(
          other.renameRecording(recordingId: 'active', title: 'Wrong'),
          throwsA(isA<LibraryBusyException>()),
        );
      });
      expect(
        () => store.snapshotForBackup(expired),
        throwsA(isA<LibraryBusyException>()),
      );
      final foreign = RecordingStore(
        databasePath: '${directory.path}/other.db',
        databaseFactory: databaseFactoryFfi,
      );
      await backup((lease) async {
        expect(
          () => foreign.snapshotForBackup(lease),
          throwsA(isA<LibraryBusyException>()),
        );
      });
    },
  );

  test(
    'expired purge waits through task and executes after cancellation/failure',
    () async {
      final release = Completer<void>();
      final task = backup((lease) async {
        await release.future;
        throw StateError('export failed');
      });
      await tick();
      final purge = store.purgeExpiredRecordings(now: now);
      await tick();
      expect(await File(recording('expired').filePath).exists(), isTrue);
      expect((await store.listRecentlyDeleted()).length, 2);
      final assertion = expectLater(task, throwsStateError);
      release.complete();
      await assertion;
      expect(await purge, isEmpty);
      expect(await File(recording('expired').filePath).exists(), isFalse);
      expect((await store.listRecentlyDeleted()).single.id, 'deleted');
    },
  );

  test(
    'already accepted file deletion prevents backup admission until file and index settle',
    () async {
      final deleting = Completer<void>();
      final release = Completer<void>();
      final slow = RecordingStore(
        databasePath: store.databasePath,
        databaseFactory: databaseFactoryFfi,
        deleteAudioFile: (name) async {
          deleting.complete();
          await release.future;
          await File(name).delete();
        },
      );
      final deletion = slow.permanentlyDeleteRecording('deleted');
      await deleting.future;
      await expectLater(
        backup((_) async {}),
        throwsA(isA<LibraryBusyException>()),
      );
      release.complete();
      await deletion;
      await backup((lease) async {
        expect(
          (await store.snapshotForBackup(
            lease,
          )).allRecordingIds.contains('deleted'),
          isFalse,
        );
      });
    },
  );

  test(
    'owned transaction rolls back; failure releases lock without changing original data',
    () async {
      await expectLater(
        backup((lease) async {
          await store.backupTransaction<void>(lease, (txn) async {
            await txn.update(
              'recordings',
              {'title': 'Bad'},
              where: 'id = ?',
              whereArgs: ['active'],
            );
            throw StateError('injected');
          });
        }),
        throwsStateError,
      );
      expect(store.coordinator.isProtected, isFalse);
      expect((await store.listRecordings()).single.title, 'active');
      await store.renameRecording(recordingId: 'active', title: 'Usable');
      await store.close();
      expect((await store.listRecordings()).single.title, 'Usable');
    },
  );
}
