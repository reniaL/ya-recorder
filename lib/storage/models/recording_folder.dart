class RecordingFolder {
  const RecordingFolder({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  Map<String, Object?> toDatabaseMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.toUtc().millisecondsSinceEpoch,
    };
  }

  factory RecordingFolder.fromDatabaseMap(Map<String, Object?> map) {
    return RecordingFolder(
      id: map['id']! as String,
      name: map['name']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at']! as int,
        isUtc: true,
      ),
    );
  }
}