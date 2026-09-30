import 'package:sqflite/sqflite.dart' as sqflite;

import 'models/recording.dart';
import 'models/recording_folder.dart';

enum FolderDeletionAction {
  moveRecordingsToAll,
  moveRecordingsToRecentlyDeleted,
}

class RecordingStore {
  RecordingStore({
    required this.databasePath,
    sqflite.DatabaseFactory? databaseFactory,
  }) : _databaseFactory = databaseFactory ?? sqflite.databaseFactory;

  static const _schemaVersion = 1;

  final String databasePath;
  final sqflite.DatabaseFactory _databaseFactory;

  sqflite.Database? _database;
  Future<sqflite.Database>? _openingDatabase;

  Future<void> open() async {
    await _openDatabase();
  }

  Future<void> close() async {
    final openingDatabase = _openingDatabase;
    if (openingDatabase != null) {
      await openingDatabase;
    }

    final database = _database;
    if (database == null) {
      return;
    }

    _database = null;
    await database.close();
  }

  Future<RecordingFolder> createFolder({
    required String id,
    required String name,
    DateTime? createdAt,
  }) async {
    _requireNonEmpty(id, 'id');
    final normalizedName = name.trim();
    _requireNonEmpty(normalizedName, 'name');

    final folder = RecordingFolder(
      id: id,
      name: normalizedName,
      createdAt: createdAt ?? DateTime.now().toUtc(),
    );
    final database = await _openDatabase();
    await database.insert('folders', folder.toDatabaseMap());
    return folder;
  }

  Future<List<RecordingFolder>> listFolders() async {
    final database = await _openDatabase();
    final rows = await database.query(
      'folders',
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(RecordingFolder.fromDatabaseMap).toList();
  }

  Future<void> renameFolder({
    required String folderId,
    required String name,
  }) async {
    _requireNonEmpty(folderId, 'folderId');
    final normalizedName = name.trim();
    _requireNonEmpty(normalizedName, 'name');
    final database = await _openDatabase();
    final updatedCount = await database.update(
      'folders',
      {'name': normalizedName},
      where: 'id = ?',
      whereArgs: [folderId],
    );
    _requireSingleFolder(updatedCount, folderId);
  }

  Future<void> deleteFolder({
    required String folderId,
    FolderDeletionAction? action,
    DateTime? deletedAt,
  }) async {
    _requireNonEmpty(folderId, 'folderId');
    final database = await _openDatabase();
    await database.transaction((transaction) async {
      final activeRecordings = await transaction.query(
        'recordings',
        columns: ['id'],
        where: 'folder_id = ? AND deleted_at IS NULL',
        whereArgs: [folderId],
        limit: 1,
      );
      if (activeRecordings.isNotEmpty) {
        if (action == null) {
          throw StateError(
            'An action is required before deleting a non-empty folder.',
          );
        }
        switch (action) {
          case FolderDeletionAction.moveRecordingsToAll:
            await transaction.update(
              'recordings',
              {'folder_id': null},
              where: 'folder_id = ? AND deleted_at IS NULL',
              whereArgs: [folderId],
            );
          case FolderDeletionAction.moveRecordingsToRecentlyDeleted:
            await transaction.update(
              'recordings',
              {
                'deleted_at': (deletedAt ?? DateTime.now())
                    .toUtc()
                    .millisecondsSinceEpoch,
              },
              where: 'folder_id = ? AND deleted_at IS NULL',
              whereArgs: [folderId],
            );
        }
      }

      final deletedCount = await transaction.delete(
        'folders',
        where: 'id = ?',
        whereArgs: [folderId],
      );
      _requireSingleFolder(deletedCount, folderId);
    });
  }

  Future<void> saveRecording(Recording recording) async {
    _validateRecording(recording);
    final database = await _openDatabase();

    await database.transaction((transaction) async {
      await _ensureFolderExists(transaction, recording.folderId);
      await transaction.insert('recordings', recording.toDatabaseMap());
    });
  }

  Future<List<Recording>> listRecordings({String? folderId}) async {
    final database = await _openDatabase();
    final whereClauses = <String>['deleted_at IS NULL'];
    final whereArguments = <Object?>[];

    if (folderId != null) {
      whereClauses.add('folder_id = ?');
      whereArguments.add(folderId);
    }

    final rows = await database.query(
      'recordings',
      where: whereClauses.join(' AND '),
      whereArgs: whereArguments,
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(Recording.fromDatabaseMap).toList();
  }

  Future<List<Recording>> listRecentlyDeleted() async {
    final database = await _openDatabase();
    final rows = await database.query(
      'recordings',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC, id DESC',
    );
    return rows.map(Recording.fromDatabaseMap).toList();
  }

  Future<void> moveRecording({
    required String recordingId,
    String? folderId,
  }) async {
    _requireNonEmpty(recordingId, 'recordingId');
    final database = await _openDatabase();

    await database.transaction((transaction) async {
      await _ensureFolderExists(transaction, folderId);
      final updatedCount = await transaction.update(
        'recordings',
        {'folder_id': folderId},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [recordingId],
      );
      _requireSingleUpdatedRow(updatedCount, recordingId);
    });
  }

  Future<void> renameRecording({
    required String recordingId,
    required String title,
  }) async {
    _requireNonEmpty(recordingId, 'recordingId');
    final normalizedTitle = title.trim();
    _requireNonEmpty(normalizedTitle, 'title');
    final database = await _openDatabase();
    final updatedCount = await database.update(
      'recordings',
      {'title': normalizedTitle},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [recordingId],
    );
    _requireSingleUpdatedRow(updatedCount, recordingId);
  }

  Future<void> softDeleteRecording({
    required String recordingId,
    required DateTime deletedAt,
  }) async {
    _requireNonEmpty(recordingId, 'recordingId');
    final database = await _openDatabase();
    final updatedCount = await database.update(
      'recordings',
      {'deleted_at': deletedAt.toUtc().millisecondsSinceEpoch},
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [recordingId],
    );
    _requireSingleUpdatedRow(updatedCount, recordingId);
  }

  Future<void> restoreRecording(String recordingId) async {
    _requireNonEmpty(recordingId, 'recordingId');
    final database = await _openDatabase();
    final updatedCount = await database.update(
      'recordings',
      {'deleted_at': null},
      where: 'id = ? AND deleted_at IS NOT NULL',
      whereArgs: [recordingId],
    );
    _requireSingleUpdatedRow(updatedCount, recordingId);
  }

  Future<void> permanentlyDeleteRecording(String recordingId) async {
    _requireNonEmpty(recordingId, 'recordingId');
    final database = await _openDatabase();
    final deletedCount = await database.delete(
      'recordings',
      where: 'id = ? AND deleted_at IS NOT NULL',
      whereArgs: [recordingId],
    );
    _requireSingleUpdatedRow(deletedCount, recordingId);
  }

  Future<sqflite.Database> _openDatabase() {
    final database = _database;
    if (database != null) {
      return Future.value(database);
    }

    final openingDatabase = _openingDatabase;
    if (openingDatabase != null) {
      return openingDatabase;
    }

    final opening = _databaseFactory.openDatabase(
      databasePath,
      options: sqflite.OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await _createSchema(database);
        },
      ),
    );
    _openingDatabase = opening;

    return opening
        .then((database) {
          _database = database;
          return database;
        })
        .whenComplete(() {
          _openingDatabase = null;
        });
  }

  static Future<void> _createSchema(sqflite.Database database) async {
    await database.execute('''
      CREATE TABLE folders (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        created_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE recordings (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        file_path TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL CHECK(duration_ms >= 0),
        file_size_bytes INTEGER NOT NULL CHECK(file_size_bytes >= 0),
        folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL,
        deleted_at INTEGER,
        was_interrupted INTEGER NOT NULL DEFAULT 0
          CHECK(was_interrupted IN (0, 1))
      )
    ''');
    await database.execute('''
      CREATE INDEX recordings_active_by_folder_and_date
      ON recordings(folder_id, deleted_at, created_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX recordings_deleted_by_date
      ON recordings(deleted_at DESC)
    ''');
  }

  static Future<void> _ensureFolderExists(
    sqflite.DatabaseExecutor executor,
    String? folderId,
  ) async {
    if (folderId == null) {
      return;
    }

    final folders = await executor.query(
      'folders',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [folderId],
      limit: 1,
    );
    if (folders.isEmpty) {
      throw StateError('Folder $folderId does not exist.');
    }
  }

  static void _validateRecording(Recording recording) {
    _requireNonEmpty(recording.id, 'recording.id');
    _requireNonEmpty(recording.title.trim(), 'recording.title');
    _requireNonEmpty(recording.filePath, 'recording.filePath');
    if (recording.duration.isNegative) {
      throw ArgumentError.value(
        recording.duration,
        'recording.duration',
        'must not be negative',
      );
    }
    if (recording.fileSizeBytes < 0) {
      throw ArgumentError.value(
        recording.fileSizeBytes,
        'recording.fileSizeBytes',
        'must not be negative',
      );
    }
    if (recording.isDeleted) {
      throw ArgumentError.value(
        recording,
        'recording',
        'must be active when first saved',
      );
    }
  }

  static void _requireNonEmpty(String value, String parameterName) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, parameterName, 'must not be empty');
    }
  }

  static void _requireSingleUpdatedRow(int affectedRows, String recordingId) {
    if (affectedRows != 1) {
      throw StateError('Active recording $recordingId was not found.');
    }
  }

  static void _requireSingleFolder(int affectedRows, String folderId) {
    if (affectedRows != 1) {
      throw StateError('Folder $folderId was not found.');
    }
  }
}
