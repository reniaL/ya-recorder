import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ya_recorder/backup/backup_contract.dart';

/// Synthetic content tests container integrity, not media decodability.
class BackupFixture {
  BackupFixture({bool empty = false}) {
    metadata = {
      'folders': [
        {
          'id': 'folder-1720000000000000',
          'name': '旧文件夹',
          'created_at': timestamp,
          'sort_order': 0,
        },
        {
          'id': 'folder-11111111-1111-4111-8111-111111111111',
          'name': 'Empty folder',
          'created_at': timestamp,
          'sort_order': 1,
        },
      ],
      'recordings': [
        if (!empty)
          for (final format in ['aac', 'mp3', 'm4a'])
            {
              'id': 'sample-$format',
              'title': '录音 $format',
              'created_at': timestamp,
              'duration_ms': 1500,
              'format': format,
              'path': 'recordings/recording-sample-$format.$format',
              'file_size_bytes': 3,
              'folder_id': 'folder-1720000000000000',
              'was_interrupted': format == 'mp3',
            },
      ],
    };
    // Mirror jsonDecode's mutable dynamic maps for malformed-input fixtures.
    metadata = jsonDecode(jsonEncode(metadata)) as Map<String, dynamic>;
    if (!empty) {
      for (final format in ['aac', 'mp3', 'm4a']) {
        audio['recordings/recording-sample-$format.$format'] = [1, 2, 3];
      }
    }
  }

  static const timestamp = '2026-10-15T06:30:00.000Z';
  late Map<String, dynamic> metadata;
  final audio = <String, List<int>>{};
  late Map<String, dynamic> manifest;
  late List<int> manifestBytes;
  late List<int> metadataBytes;
  late List<BackupEntry> entries;

  void assemble({void Function(Map<String, dynamic>)? editManifest}) {
    metadataBytes = utf8.encode(jsonEncode(metadata));
    final files = {'metadata.json': metadataBytes, ...audio};
    manifest = {
      'backup_type': BackupContract.backupType,
      'format_version': 1,
      'created_at': timestamp,
      'recording_count': (metadata['recordings'] as List).length,
      'folder_count': (metadata['folders'] as List).length,
      'files': [
        for (final entry in files.entries)
          {
            'path': entry.key,
            'size_bytes': entry.value.length,
            'sha256': sha256.convert(entry.value).toString(),
          },
      ],
    };
    editManifest?.call(manifest);
    manifestBytes = utf8.encode(jsonEncode(manifest));
    entries = [
      BackupEntry(path: 'manifest.json', size: manifestBytes.length),
      for (final entry in files.entries)
        BackupEntry(path: entry.key, size: entry.value.length),
    ];
  }

  BackupDocument parse([BackupContract contract = const BackupContract()]) =>
      contract.parse(
        manifestBytes: manifestBytes,
        metadataBytes: metadataBytes,
        entries: entries,
      );
}
