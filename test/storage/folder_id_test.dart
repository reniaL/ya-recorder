import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/storage/folder_id.dart';
import 'package:ya_recorder/storage/models/recording.dart';
import 'package:ya_recorder/storage/recording_store.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'new UUID folders coexist with timestamp IDs without migrating references',
    () async {
      final directory = await Directory.systemTemp.createTemp('folder-uuid-');
      final store = RecordingStore(
        databasePath: '${directory.path}/index.db',
        databaseFactory: databaseFactoryFfi,
      );
      const legacyId = 'folder-1720000000000000';
      final newId = newFolderId();
      expect(
        newId,
        matches(
          RegExp(
            r'^folder-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      try {
        await store.createFolder(id: legacyId, name: 'Legacy');
        await store.createFolder(id: newId, name: 'New');
        final audio = File('${directory.path}/original.m4a');
        await audio.writeAsBytes([1, 2, 3]);
        final recording = Recording(
          id: 'old-recording',
          title: 'Original',
          filePath: audio.path,
          createdAt: DateTime.utc(2026, 10, 1),
          duration: const Duration(seconds: 1),
          fileSizeBytes: 3,
          format: RecordingFormat.m4a,
          folderId: legacyId,
        );
        await store.saveRecording(recording);
        await store.close();
        expect((await store.listFolders()).map((f) => f.id), [legacyId, newId]);
        expect(
          (await store.listRecordings()).single.toDatabaseMap(),
          recording.toDatabaseMap(),
        );
        await store.moveRecording(recordingId: recording.id, folderId: newId);
        await store.renameFolder(folderId: newId, name: 'Renamed');
        await store.reorderFolders([newId, legacyId]);
        await store.close();
        expect((await store.listFolders()).map((f) => f.id), [newId, legacyId]);
        expect((await store.listRecordings()).single.folderId, newId);
        expect(await audio.readAsBytes(), [1, 2, 3]);
      } finally {
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
