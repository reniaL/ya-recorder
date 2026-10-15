import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../recording/recording_format.dart';

enum BackupErrorCode {
  unsupportedVersion,
  invalidMetadata,
  invalidEntry,
  duplicateEntry,
  encryptedArchive,
  resourceLimit,
  missingFile,
  checksumMismatch,
}

class BackupValidationException implements Exception {
  const BackupValidationException(this.code, this.detail);
  final BackupErrorCode code;
  final String detail;

  @override
  String toString() => 'BackupValidationException(${code.name}: $detail)';
}

/// Resource policy, not an application recording-duration limit.
class BackupLimits {
  const BackupLimits({
    this.maxRecordings = 10000,
    this.maxFolders = 10000,
    this.maxAudioBytes = 16 * 1024 * 1024 * 1024,
    this.maxJsonBytes = 16 * 1024 * 1024,
    this.maxTextLength = 4096,
  });

  final int maxRecordings;
  final int maxFolders;
  final int maxAudioBytes;
  final int maxJsonBytes;
  final int maxTextLength;
}

/// ZIP adapter must provide every raw entry (before any name deduplication).
/// v1 only accepts STORE entries, without directories, links or encryption.
class BackupEntry {
  const BackupEntry({
    required this.path,
    required this.size,
    this.isFile = true,
    this.isSymbolicLink = false,
    this.isEncrypted = false,
    this.compressionMethod = 0,
  });

  final String path;
  final int size;
  final bool isFile;
  final bool isSymbolicLink;
  final bool isEncrypted;
  final int compressionMethod;
}

class BackupFile {
  const BackupFile(this.path, this.size, this.sha256Hex);
  final String path;
  final int size;
  final String sha256Hex;

  Map<String, Object?> toJson() => {
    'path': path,
    'size_bytes': size,
    'sha256': sha256Hex,
  };
}

class BackupFolder {
  const BackupFolder(this.id, this.name, this.createdAt, this.sortOrder);
  final String id;
  final String name;
  final DateTime createdAt;
  final int sortOrder;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'created_at': createdAt.toUtc().toIso8601String(),
    'sort_order': sortOrder,
  };
}

class BackupRecording {
  const BackupRecording({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.durationMs,
    required this.format,
    required this.file,
    required this.folderId,
    required this.wasInterrupted,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final int durationMs;
  final RecordingFormat format;
  final BackupFile file;
  final String? folderId;
  final bool wasInterrupted;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'created_at': createdAt.toUtc().toIso8601String(),
    'duration_ms': durationMs,
    'format': format.wireName,
    'path': file.path,
    'file_size_bytes': file.size,
    'folder_id': folderId,
    'was_interrupted': wasInterrupted,
  };
}

/// Validated metadata and entry inventory. Audio content still needs verification
/// using [BackupContract.verifyContent] before a caller may report a valid pack.
class BackupDocument {
  BackupDocument({
    required this.createdAt,
    required List<BackupFile> files,
    required List<BackupFolder> folders,
    required List<BackupRecording> recordings,
  }) : files = List.unmodifiable(files),
       folders = List.unmodifiable(folders),
       recordings = List.unmodifiable(recordings);

  final DateTime createdAt;
  final List<BackupFile> files;
  final List<BackupFolder> folders;
  final List<BackupRecording> recordings;

  Map<String, Object?> manifestJson() => {
    'backup_type': BackupContract.backupType,
    'format_version': BackupContract.version,
    'created_at': createdAt.toUtc().toIso8601String(),
    'recording_count': recordings.length,
    'folder_count': folders.length,
    'files': files.map((file) => file.toJson()).toList(),
  };

  Map<String, Object?> metadataJson() => {
    'folders': folders.map((folder) => folder.toJson()).toList(),
    'recordings': recordings.map((recording) => recording.toJson()).toList(),
  };
}

class BackupContract {
  const BackupContract({this.limits = const BackupLimits()});
  static const backupType = 'io.github.renial.ya_recorder.backup';
  static const version = 1;
  final BackupLimits limits;

  Never _fail(BackupErrorCode code, String detail) =>
      throw BackupValidationException(code, detail);

  /// No file extraction or database writes. The adapter is responsible for
  /// limiting ZIP directory allocation before constructing [entries].
  BackupDocument parse({
    required List<int> manifestBytes,
    required List<int> metadataBytes,
    required List<BackupEntry> entries,
  }) {
    if (entries.length > limits.maxRecordings + 2) {
      _fail(BackupErrorCode.resourceLimit, 'entry count');
    }
    final inventory = <String, BackupEntry>{};
    var total = 0;
    for (final entry in entries) {
      if (entry.isEncrypted) {
        _fail(BackupErrorCode.encryptedArchive, entry.path);
      }
      if (!entry.isFile ||
          entry.isSymbolicLink ||
          entry.compressionMethod != 0 ||
          !_safePath(entry.path) ||
          entry.size < 0) {
        _fail(BackupErrorCode.invalidEntry, entry.path);
      }
      if (inventory.containsKey(entry.path)) {
        _fail(BackupErrorCode.duplicateEntry, entry.path);
      }
      inventory[entry.path] = entry;
      total += entry.size;
      final isJson =
          entry.path == 'manifest.json' || entry.path == 'metadata.json';
      if (isJson && entry.size > limits.maxJsonBytes ||
          !isJson && entry.size > limits.maxAudioBytes ||
          total > limits.maxAudioBytes + 2 * limits.maxJsonBytes) {
        _fail(BackupErrorCode.resourceLimit, entry.path);
      }
    }
    for (final name in ['manifest.json', 'metadata.json']) {
      if (!inventory.containsKey(name)) {
        _fail(BackupErrorCode.missingFile, name);
      }
    }
    if (inventory['manifest.json']!.size != manifestBytes.length ||
        inventory['metadata.json']!.size != metadataBytes.length) {
      _fail(BackupErrorCode.invalidEntry, 'JSON size');
    }
    final manifest = _json(manifestBytes);
    _keys(manifest, [
      'backup_type',
      'format_version',
      'created_at',
      'recording_count',
      'folder_count',
      'files',
    ]);
    if (manifest['backup_type'] != backupType) {
      _fail(BackupErrorCode.invalidMetadata, 'backup_type');
    }
    if (manifest['format_version'] is! int ||
        manifest['format_version'] != version) {
      _fail(BackupErrorCode.unsupportedVersion, 'format_version');
    }
    final createdAt = _date(manifest['created_at']);
    final files = <String, BackupFile>{};
    for (final value in _list(manifest['files'], limits.maxRecordings + 1)) {
      final item = _map(value);
      _keys(item, ['path', 'size_bytes', 'sha256']);
      final path = _text(item['path']);
      final hash = _text(item['sha256']);
      if (!_safePath(path) ||
          path == 'manifest.json' ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
        _fail(BackupErrorCode.invalidMetadata, 'file path/hash');
      }
      if (files.containsKey(path)) _fail(BackupErrorCode.duplicateEntry, path);
      final file = BackupFile(path, _int(item['size_bytes']), hash);
      final entry = inventory[path];
      if (entry == null) _fail(BackupErrorCode.missingFile, path);
      if (entry.size != file.size) _fail(BackupErrorCode.invalidEntry, path);
      files[path] = file;
    }
    if (files.length != inventory.length - 1 ||
        !files.containsKey('metadata.json')) {
      _fail(BackupErrorCode.invalidEntry, 'file inventory');
    }
    final metadataFile = files['metadata.json']!;
    if (sha256.convert(metadataBytes).toString() != metadataFile.sha256Hex) {
      _fail(BackupErrorCode.checksumMismatch, 'metadata.json');
    }
    final metadata = _json(metadataBytes);
    _keys(metadata, ['folders', 'recordings']);
    final folders = <BackupFolder>[];
    final folderIds = <String>{};
    final folderNames = <String>{};
    for (final value in _list(metadata['folders'], limits.maxFolders)) {
      final item = _map(value);
      _keys(item, ['id', 'name', 'created_at', 'sort_order']);
      final id = _id(item['id']);
      final name = _text(item['name']);
      // Match SQLite NOCASE's ASCII-only folding, not Unicode lowercasing.
      final folded = name.replaceAllMapped(
        RegExp('[A-Z]'),
        (m) => m[0]!.toLowerCase(),
      );
      if (!folderIds.add(id) || !folderNames.add(folded)) {
        _fail(BackupErrorCode.duplicateEntry, 'folder');
      }
      if (name.trim() != name) {
        _fail(BackupErrorCode.invalidMetadata, 'folder name');
      }
      folders.add(
        BackupFolder(
          id,
          name,
          _date(item['created_at']),
          _int(item['sort_order']),
        ),
      );
    }
    final recordings = <BackupRecording>[];
    final recordingIds = <String>{};
    var audioBytes = 0;
    for (final value in _list(metadata['recordings'], limits.maxRecordings)) {
      final item = _map(value);
      _keys(item, [
        'id',
        'title',
        'created_at',
        'duration_ms',
        'format',
        'path',
        'file_size_bytes',
        'folder_id',
        'was_interrupted',
      ]);
      final id = _id(item['id']);
      if (!recordingIds.add(id)) _fail(BackupErrorCode.duplicateEntry, id);
      final format = RecordingFormat.values.where(
        (f) => f.wireName == item['format'],
      );
      if (format.isEmpty) _fail(BackupErrorCode.invalidMetadata, 'format');
      final path = _text(item['path']);
      if (path != 'recordings/recording-$id.${format.single.extension}') {
        _fail(BackupErrorCode.invalidMetadata, 'recording path');
      }
      final file = files[path];
      if (file == null) _fail(BackupErrorCode.missingFile, path);
      if (file.size != _int(item['file_size_bytes']) || file.size == 0) {
        _fail(BackupErrorCode.invalidMetadata, 'audio size');
      }
      audioBytes += file.size;
      if (audioBytes > limits.maxAudioBytes) {
        _fail(BackupErrorCode.resourceLimit, 'audio total');
      }
      final folderId = item['folder_id'] == null
          ? null
          : _id(item['folder_id']);
      if (folderId != null && !folderIds.contains(folderId)) {
        _fail(BackupErrorCode.invalidMetadata, 'folder reference');
      }
      if (item['was_interrupted'] is! bool) {
        _fail(BackupErrorCode.invalidMetadata, 'was_interrupted');
      }
      recordings.add(
        BackupRecording(
          id: id,
          title: _text(item['title']),
          createdAt: _date(item['created_at']),
          durationMs: _int(item['duration_ms']),
          format: format.single,
          file: file,
          folderId: folderId,
          wasInterrupted: item['was_interrupted'] as bool,
        ),
      );
    }
    if (_int(manifest['recording_count']) != recordings.length ||
        _int(manifest['folder_count']) != folders.length ||
        files.length != recordings.length + 1) {
      _fail(BackupErrorCode.invalidMetadata, 'counts/unreferenced files');
    }
    return BackupDocument(
      createdAt: createdAt,
      files: files.values.toList(),
      folders: folders,
      recordings: recordings,
    );
  }

  /// Hash actual content in chunks, including entries that import will skip.
  /// A size claim never permits reading more than the declared length.
  Future<void> verifyContent(BackupFile file, Stream<List<int>> chunks) async {
    var size = 0;
    final digest = await sha256
        .bind(
          chunks.map((chunk) {
            size += chunk.length;
            if (size > file.size) {
              _fail(BackupErrorCode.invalidEntry, file.path);
            }
            return chunk;
          }),
        )
        .single;
    if (size != file.size) _fail(BackupErrorCode.invalidEntry, file.path);
    if (digest.toString() != file.sha256Hex) {
      _fail(BackupErrorCode.checksumMismatch, file.path);
    }
  }

  bool _safePath(String path) =>
      path == 'manifest.json' ||
      path == 'metadata.json' ||
      RegExp(
        r'^recordings/recording-[A-Za-z0-9_-]{1,128}\.(aac|mp3|m4a)$',
      ).hasMatch(path);

  Map<String, Object?> _json(List<int> bytes) {
    if (bytes.length > limits.maxJsonBytes) {
      _fail(BackupErrorCode.resourceLimit, 'JSON');
    }
    try {
      return _map(jsonDecode(utf8.decode(bytes)));
    } on FormatException {
      _fail(BackupErrorCode.invalidMetadata, 'JSON encoding');
    }
  }

  Map<String, Object?> _map(Object? value) {
    if (value is! Map<String, Object?>) {
      _fail(BackupErrorCode.invalidMetadata, 'object');
    }
    return value;
  }

  void _keys(Map<String, Object?> map, List<String> keys) {
    if (map.length != keys.length || !keys.every(map.containsKey)) {
      _fail(BackupErrorCode.invalidMetadata, 'fields');
    }
  }

  List<Object?> _list(Object? value, int max) {
    if (value is! List<Object?>) {
      _fail(BackupErrorCode.invalidMetadata, 'array');
    }
    if (value.length > max) _fail(BackupErrorCode.resourceLimit, 'array');
    return value;
  }

  String _text(Object? value) {
    if (value is! String || value.trim().isEmpty || value.contains('\u0000')) {
      _fail(BackupErrorCode.invalidMetadata, 'text');
    }
    if (value.length > limits.maxTextLength) {
      _fail(BackupErrorCode.resourceLimit, 'text');
    }
    return value;
  }

  String _id(Object? value) {
    final id = _text(value);
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      _fail(BackupErrorCode.invalidMetadata, 'id');
    }
    return id;
  }

  int _int(Object? value) {
    if (value is! int || value < 0 || value > 9007199254740991) {
      _fail(BackupErrorCode.invalidMetadata, 'integer');
    }
    return value;
  }

  DateTime _date(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(\d{3})?Z$',
        ).hasMatch(value)) {
      _fail(BackupErrorCode.invalidMetadata, 'UTC timestamp');
    }
    final date = DateTime.tryParse(value);
    if (date == null || date.toIso8601String() != value) {
      _fail(BackupErrorCode.invalidMetadata, 'UTC timestamp');
    }
    return date;
  }
}
