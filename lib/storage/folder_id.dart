import 'package:uuid/uuid.dart';

/// Only new folders use UUIDs. Existing IDs are never rewritten.
String newFolderId() => 'folder-${const Uuid().v4()}';
