class RecordingFolder {
  const RecordingFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int sortOrder;

  Map<String, Object?> toDatabaseMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.toUtc().millisecondsSinceEpoch,
      'sort_order': sortOrder,
    };
  }

  factory RecordingFolder.fromDatabaseMap(Map<String, Object?> map) {
    return RecordingFolder(
      id: map['id']! as String,
      name: map['name']! as String,
      sortOrder: map['sort_order'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at']! as int,
        isUtc: true,
      ),
    );
  }
}
