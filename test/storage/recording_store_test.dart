import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/storage/app_storage_paths.dart';
import 'package:ya_recorder/storage/models/recording.dart';
import 'package:ya_recorder/storage/recording_store.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('RecordingStore', () {
    late Directory temporaryDirectory;
    late String databasePath;
    late RecordingStore store;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'ya-recorder-',
      );
      databasePath = path.join(temporaryDirectory.path, 'index.db');
      store = RecordingStore(
        databasePath: databasePath,
        databaseFactory: databaseFactoryFfi,
      );
      await store.open();
    });

    tearDown(() async {
      await store.close();
      await temporaryDirectory.delete(recursive: true);
    });

    test(
      'persists folders, active recordings, and recently deleted recordings',
      () async {
        final createdAt = DateTime.utc(2026, 9, 29, 8);
        await store.createFolder(
          id: 'folder-interviews',
          name: 'Interviews',
          createdAt: createdAt,
        );
        await store.saveRecording(
          Recording(
            id: 'recording-active',
            title: 'Planning session',
            filePath: '/private/recording-active.m4a',
            createdAt: createdAt,
            duration: const Duration(minutes: 5),
            fileSizeBytes: 1024,
            folderId: 'folder-interviews',
          ),
        );
        await store.saveRecording(
          Recording(
            id: 'recording-deleted',
            title: 'Discarded take',
            filePath: '/private/recording-deleted.m4a',
            createdAt: createdAt.add(const Duration(minutes: 1)),
            duration: const Duration(seconds: 12),
            fileSizeBytes: 512,
            folderId: 'folder-interviews',
            wasInterrupted: true,
          ),
        );
        await store.softDeleteRecording(
          recordingId: 'recording-deleted',
          deletedAt: createdAt.add(const Duration(days: 1)),
        );

        await store.close();
        store = RecordingStore(
          databasePath: databasePath,
          databaseFactory: databaseFactoryFfi,
        );
        await store.open();

        final folders = await store.listFolders();
        final activeRecordings = await store.listRecordings(
          folderId: 'folder-interviews',
        );
        final recentlyDeleted = await store.listRecentlyDeleted();

        expect(folders.single.name, 'Interviews');
        expect(activeRecordings.single.id, 'recording-active');
        expect(recentlyDeleted.single.id, 'recording-deleted');
        expect(recentlyDeleted.single.wasInterrupted, isTrue);
        expect(
          recentlyDeleted.single.deletedAt,
          createdAt.add(const Duration(days: 1)),
        );
      },
    );

    test('rejects recording data that references a missing folder', () async {
      final recording = Recording(
        id: 'orphaned-recording',
        title: 'Unassigned',
        filePath: '/private/orphaned-recording.m4a',
        createdAt: DateTime.utc(2026, 9, 29),
        duration: const Duration(seconds: 1),
        fileSizeBytes: 1,
        folderId: 'missing-folder',
      );

      await expectLater(store.saveRecording(recording), throwsStateError);
    });

    test(
      'requires a non-empty, case-insensitively unique folder name',
      () async {
        await expectLater(
          store.createFolder(id: 'folder-empty', name: '   '),
          throwsArgumentError,
        );
        await store.createFolder(id: 'folder-work', name: '  Work  ');
        await expectLater(
          store.createFolder(id: 'folder-work-copy', name: 'work'),
          throwsA(isA<DatabaseException>()),
        );

        expect((await store.listFolders()).single.name, 'Work');
      },
    );

    test('renames an active recording without changing its metadata', () async {
      final createdAt = DateTime.utc(2026, 9, 29, 8);
      await store.saveRecording(
        Recording(
          id: 'recording-1',
          title: 'Original title',
          filePath: '/private/recording-1.m4a',
          createdAt: createdAt,
          duration: const Duration(seconds: 12),
          fileSizeBytes: 512,
        ),
      );

      await store.renameRecording(
        recordingId: 'recording-1',
        title: '  Renamed recording  ',
      );

      final renamed = (await store.listRecordings()).single;
      expect(renamed.title, 'Renamed recording');
      expect(renamed.filePath, '/private/recording-1.m4a');
      expect(renamed.createdAt, createdAt);
      expect(renamed.duration, const Duration(seconds: 12));
      expect(renamed.folderId, isNull);
    });

    test(
      'moves an active recording without changing its file metadata',
      () async {
        final createdAt = DateTime.utc(2026, 9, 29, 8);
        await store.createFolder(id: 'folder-work', name: 'Work');
        await store.saveRecording(
          Recording(
            id: 'recording-1',
            title: 'Planning session',
            filePath: '/private/recording-1.m4a',
            createdAt: createdAt,
            duration: const Duration(seconds: 12),
            fileSizeBytes: 512,
          ),
        );

        await store.moveRecording(
          recordingId: 'recording-1',
          folderId: 'folder-work',
        );

        final moved = (await store.listRecordings(
          folderId: 'folder-work',
        )).single;
        expect(moved.filePath, '/private/recording-1.m4a');
        expect(moved.createdAt, createdAt);
        expect(moved.duration, const Duration(seconds: 12));
        expect(moved.folderId, 'folder-work');

        await store.moveRecording(recordingId: 'recording-1');
        expect((await store.listRecordings()).single.folderId, isNull);
      },
    );

    test(
      'renames and deletes folders with an explicit recording disposition',
      () async {
        final createdAt = DateTime.utc(2026, 9, 29, 8);
        await store.createFolder(
          id: 'folder-project',
          name: 'Project',
          createdAt: createdAt,
        );
        await store.saveRecording(
          Recording(
            id: 'recording-1',
            title: 'Project update',
            filePath: '/private/recording-1.m4a',
            createdAt: createdAt,
            duration: const Duration(seconds: 12),
            fileSizeBytes: 512,
            folderId: 'folder-project',
          ),
        );

        await store.renameFolder(folderId: 'folder-project', name: '  Work  ');
        expect((await store.listFolders()).single.name, 'Work');
        expect((await store.listFolders()).single.createdAt, createdAt);
        await expectLater(
          store.deleteFolder(folderId: 'folder-project'),
          throwsStateError,
        );

        await store.deleteFolder(
          folderId: 'folder-project',
          action: FolderDeletionAction.moveRecordingsToAll,
        );
        expect(await store.listFolders(), isEmpty);
        expect((await store.listRecordings()).single.folderId, isNull);

        await store.createFolder(id: 'folder-delete', name: 'Delete');
        await store.moveRecording(
          recordingId: 'recording-1',
          folderId: 'folder-delete',
        );
        await store.deleteFolder(
          folderId: 'folder-delete',
          action: FolderDeletionAction.moveRecordingsToRecentlyDeleted,
          deletedAt: createdAt.add(const Duration(days: 1)),
        );
        expect(await store.listRecordings(), isEmpty);
        final deleted = (await store.listRecentlyDeleted()).single;
        expect(deleted.folderId, isNull);
        expect(deleted.deletedAt, createdAt.add(const Duration(days: 1)));
      },
    );
  });

  test(
    'AppStoragePaths separates completed and temporary recordings',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'ya-recorder-',
      );
      addTearDown(() => temporaryDirectory.delete(recursive: true));

      final paths = AppStoragePaths(temporaryDirectory);
      await paths.ensureDirectories();

      expect(await paths.recordingsDirectory.exists(), isTrue);
      expect(await paths.recoveryDirectory.exists(), isTrue);
      expect(
        paths.completedRecordingFile('recording-1').path,
        path.join(
          temporaryDirectory.path,
          'recordings',
          'recording-recording-1.m4a',
        ),
      );
      expect(
        paths.temporaryRecordingFile('recording-1').path,
        path.join(
          temporaryDirectory.path,
          'recovery',
          'recording-recording-1.m4a.part',
        ),
      );
      expect(
        () => paths.completedRecordingFile('../recording'),
        throwsArgumentError,
      );
    },
  );
}
