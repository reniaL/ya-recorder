class Recording {
  const Recording({
    required this.id,
    required this.title,
    required this.filePath,
    required this.createdAt,
    required this.duration,
    required this.fileSizeBytes,
    this.folderId,
    this.deletedAt,
    this.wasInterrupted = false,
  });

  final String id;
  final String title;
  final String filePath;
  final DateTime createdAt;
  final Duration duration;
  final int fileSizeBytes;
  final String? folderId;
  final DateTime? deletedAt;
  final bool wasInterrupted;

  bool get isDeleted => deletedAt != null;

  Map<String, Object?> toDatabaseMap() {
    return {
      'id': id,
      'title': title,
      'file_path': filePath,
      'created_at': createdAt.toUtc().millisecondsSinceEpoch,
      'duration_ms': duration.inMilliseconds,
      'file_size_bytes': fileSizeBytes,
      'folder_id': folderId,
      'deleted_at': deletedAt?.toUtc().millisecondsSinceEpoch,
      'was_interrupted': wasInterrupted ? 1 : 0,
    };
  }

  factory Recording.fromDatabaseMap(Map<String, Object?> map) {
    return Recording(
      id: map['id']! as String,
      title: map['title']! as String,
      filePath: map['file_path']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at']! as int,
        isUtc: true,
      ),
      duration: Duration(milliseconds: map['duration_ms']! as int),
      fileSizeBytes: map['file_size_bytes']! as int,
      folderId: map['folder_id'] as String?,
      deletedAt: _dateTimeOrNull(map['deleted_at']),
      wasInterrupted: (map['was_interrupted']! as int) == 1,
    );
  }

  static DateTime? _dateTimeOrNull(Object? value) {
    if (value == null) {
      return null;
    }

    return DateTime.fromMillisecondsSinceEpoch(value as int, isUtc: true);
  }
}