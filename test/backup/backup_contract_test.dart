import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ya_recorder/backup/backup_contract.dart';
import 'package:ya_recorder/backup/backup_progress.dart';

import 'backup_fixture.dart';

Matcher error(BackupErrorCode code) =>
    isA<BackupValidationException>().having((e) => e.code, 'code', code);

void main() {
  test(
    'ZIP64-sized descriptors stay 64-bit without loading claimed content',
    () {
      const largeSize = 5 * 1024 * 1024 * 1024;
      final fixture = BackupFixture();
      fixture.metadata['recordings'][0]['file_size_bytes'] = largeSize;
      fixture.assemble(
        editManifest: (manifest) {
          manifest['files'][1]['size_bytes'] = largeSize;
        },
      );
      fixture.entries[2] = const BackupEntry(
        path: 'recordings/recording-sample-aac.aac',
        size: largeSize,
      );
      expect(fixture.parse().recordings.first.file.size, largeSize);
    },
  );
  test('three formats, old/new IDs and metadata round-trip', () async {
    final fixture = BackupFixture()..assemble();
    final document = fixture.parse();
    expect(document.recordings.map((r) => r.format.wireName), [
      'aac',
      'mp3',
      'm4a',
    ]);
    expect(document.metadataJson(), fixture.metadata);
    expect(document.manifestJson(), fixture.manifest);
    expect(
      document.recordings.last.file.path,
      'recordings/recording-sample-m4a.m4a',
    );
    expect(() => document.recordings.clear(), throwsUnsupportedError);
    for (final file in document.files) {
      final bytes = file.path == 'metadata.json'
          ? fixture.metadataBytes
          : fixture.audio[file.path]!;
      await const BackupContract().verifyContent(
        file,
        Stream.fromIterable([bytes.sublist(0, 1), bytes.sublist(1)]),
      );
    }
  });

  test(
    'empty recordings and empty folder preserved; truly empty library valid',
    () {
      final fixture = BackupFixture(empty: true)..assemble();
      expect(fixture.parse().folders.length, 2);
      fixture.metadata['folders'] = [];
      fixture.assemble();
      expect(fixture.parse().recordings, isEmpty);
      expect(fixture.parse().files.single.path, 'metadata.json');
    },
  );

  for (final version in [2, '1', 1.0]) {
    test('reject unsupported version $version (${version.runtimeType})', () {
      final fixture = BackupFixture()
        ..assemble(editManifest: (m) => m['format_version'] = version);
      expect(fixture.parse, throwsA(error(BackupErrorCode.unsupportedVersion)));
    });
  }

  test(
    'wrong identity and unknown fields (settings/deleted/path) rejected',
    () {
      final fixture = BackupFixture()
        ..assemble(editManifest: (m) => m['backup_type'] = 'other');
      expect(fixture.parse, throwsA(error(BackupErrorCode.invalidMetadata)));
      for (final field in ['settings', 'deleted_at', 'file_path']) {
        final f = BackupFixture();
        if (field == 'settings') {
          f.metadata[field] = {};
        } else {
          f.metadata['recordings'][0][field] = '/original/phone';
        }
        f.assemble();
        expect(f.parse, throwsA(error(BackupErrorCode.invalidMetadata)));
      }
    },
  );

  test('duplicate ZIP names remain visible and are rejected', () {
    final fixture = BackupFixture()..assemble();
    fixture.entries.add(fixture.entries.last);
    expect(fixture.parse, throwsA(error(BackupErrorCode.duplicateEntry)));
  });

  for (final path in [
    '../metadata.json',
    '/metadata.json',
    r'C:\metadata.json',
    r'recordings\recording-a.aac',
    'recordings/../metadata.json',
    'recordings/recording-a%2fb.aac',
    'recordings/recording-a.aac/',
  ]) {
    test('reject unsafe path $path', () {
      final fixture = BackupFixture()..assemble();
      fixture.entries.add(BackupEntry(path: path, size: 1));
      expect(fixture.parse, throwsA(error(BackupErrorCode.invalidEntry)));
    });
  }

  test('encrypted, links, directories and compressed entries rejected', () {
    for (final entry in [
      const BackupEntry(path: 'metadata.json', size: 1, isEncrypted: true),
      const BackupEntry(path: 'metadata.json', size: 1, isSymbolicLink: true),
      const BackupEntry(path: 'metadata.json', size: 1, isFile: false),
      const BackupEntry(path: 'metadata.json', size: 1, compressionMethod: 8),
    ]) {
      final fixture = BackupFixture()..assemble();
      fixture.entries[1] = entry;
      expect(
        fixture.parse,
        throwsA(
          error(
            entry.isEncrypted
                ? BackupErrorCode.encryptedArchive
                : BackupErrorCode.invalidEntry,
          ),
        ),
      );
    }
  });

  test('missing and undeclared entries rejected', () {
    final missing = BackupFixture()..assemble();
    missing.entries.removeLast();
    expect(missing.parse, throwsA(error(BackupErrorCode.missingFile)));
    final extra = BackupFixture()..assemble();
    extra.entries.add(
      const BackupEntry(path: 'recordings/recording-extra.aac', size: 3),
    );
    expect(extra.parse, throwsA(error(BackupErrorCode.invalidEntry)));
  });

  test('duplicate manifest files and metadata IDs rejected', () {
    final fixture = BackupFixture()
      ..assemble(editManifest: (m) => m['files'].add(m['files'][0]));
    expect(fixture.parse, throwsA(error(BackupErrorCode.duplicateEntry)));
    for (final list in ['recordings', 'folders']) {
      final f = BackupFixture();
      f.metadata[list].add(Map<String, dynamic>.from(f.metadata[list][0]));
      f.assemble();
      expect(f.parse, throwsA(error(BackupErrorCode.duplicateEntry)));
    }
  });

  test(
    'invalid folder reference and SQLite NOCASE name collision rejected',
    () {
      final fixture = BackupFixture();
      fixture.metadata['recordings'][0]['folder_id'] = 'missing';
      fixture.assemble();
      expect(fixture.parse, throwsA(error(BackupErrorCode.invalidMetadata)));
      fixture.metadata['recordings'][0]['folder_id'] = null;
      fixture.metadata['folders'][0]['name'] = 'Interviews';
      fixture.metadata['folders'][1]['name'] = 'INTERVIEWS';
      fixture.assemble();
      expect(fixture.parse, throwsA(error(BackupErrorCode.duplicateEntry)));
    },
  );

  test(
    'invalid field types, UTC timestamp, count and audio paths rejected',
    () {
      for (final changes in [
        {'created_at': '2026-02-30T06:30:00.000Z'},
        {'created_at': '2026-10-15T14:30:00.000+08:00'},
        {'duration_ms': -1},
        {'duration_ms': 1.5},
        {'format': 'wav'},
        {'was_interrupted': 1},
        {'id': 'unsafe/id'},
        {'title': ''},
        {'path': 'recordings/recording-other.aac'},
        {'file_size_bytes': 4},
      ]) {
        final fixture = BackupFixture();
        fixture.metadata['recordings'][0].addAll(changes);
        fixture.assemble();
        expect(fixture.parse, throwsA(error(BackupErrorCode.invalidMetadata)));
      }
      final fixture = BackupFixture()
        ..assemble(editManifest: (m) => m['recording_count'] = 0);
      expect(fixture.parse, throwsA(error(BackupErrorCode.invalidMetadata)));
    },
  );

  test(
    'JSON size, entry and audio resource limits enforced without allocation',
    () {
      final fixture = BackupFixture()..assemble();
      for (final limits in [
        const BackupLimits(maxRecordings: 2),
        const BackupLimits(maxFolders: 1),
        const BackupLimits(maxJsonBytes: 10),
        const BackupLimits(maxAudioBytes: 8),
        const BackupLimits(maxTextLength: 3),
      ]) {
        expect(
          () => fixture.parse(BackupContract(limits: limits)),
          throwsA(error(BackupErrorCode.resourceLimit)),
        );
      }
      fixture.entries[2] = const BackupEntry(
        path: 'recordings/recording-sample-aac.aac',
        size: 17 * 1024 * 1024 * 1024,
      );
      expect(fixture.parse, throwsA(error(BackupErrorCode.resourceLimit)));
    },
  );

  test('metadata corruption and malformed UTF8/JSON rejected', () {
    final fixture = BackupFixture()..assemble();
    fixture.metadataBytes[0] = 0;
    expect(fixture.parse, throwsA(error(BackupErrorCode.checksumMismatch)));
    for (final bytes in [
      [255],
      utf8.encode('{invalid}'),
    ]) {
      final f = BackupFixture()..assemble();
      f.manifestBytes = bytes;
      f.entries[0] = BackupEntry(path: 'manifest.json', size: bytes.length);
      expect(f.parse, throwsA(error(BackupErrorCode.invalidMetadata)));
    }
  });

  test(
    'hash actual audio, reject truncation, expansion and same-size corruption',
    () async {
      final fixture = BackupFixture()..assemble();
      final file = fixture.parse().recordings.first.file;
      for (final bytes in [
        [1],
        [1, 2, 3, 4],
      ]) {
        await expectLater(
          const BackupContract().verifyContent(file, Stream.value(bytes)),
          throwsA(error(BackupErrorCode.invalidEntry)),
        );
      }
      await expectLater(
        const BackupContract().verifyContent(file, Stream.value([3, 2, 1])),
        throwsA(error(BackupErrorCode.checksumMismatch)),
      );
    },
  );

  test(
    'real STORE ZIP can be inspected and hashed in file-backed chunks',
    () async {
      final fixture = BackupFixture()..assemble();
      final content = {
        'manifest.json': fixture.manifestBytes,
        'metadata.json': fixture.metadataBytes,
        ...fixture.audio,
      };
      final archive = Archive();
      for (final entry in content.entries) {
        archive.add(
          ArchiveFile.noCompress(entry.key, entry.value.length, entry.value),
        );
      }
      final directory = await Directory.systemTemp.createTemp(
        'backup-contract-',
      );
      final file = File('${directory.path}/sample.zip');
      InputFileStream? input;
      try {
        await file.writeAsBytes(ZipEncoder().encode(archive));
        input = InputFileStream(file.path);
        final zip = ZipDirectory()..read(input);
        expect(zip.fileHeaders.length, content.length);
        final entries = [
          for (final header in zip.fileHeaders)
            BackupEntry(
              path: header.filename,
              size: header.uncompressedSize,
              compressionMethod: header.compressionMethod,
              isEncrypted: header.generalPurposeBitFlag & 1 != 0,
            ),
        ];
        final document = const BackupContract().parse(
          manifestBytes: fixture.manifestBytes,
          metadataBytes: fixture.metadataBytes,
          entries: entries,
        );
        for (final item in document.files) {
          final header = zip.fileHeaders.singleWhere(
            (h) => h.filename == item.path,
          );
          final stream = header.file!.getStream(decompress: false);
          Stream<List<int>> chunks() async* {
            while (!stream.isEOS) {
              yield stream.readBytes(min(64, stream.length)).toUint8List();
            }
          }

          await const BackupContract().verifyContent(item, chunks());
        }
      } finally {
        input?.closeSync();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'stage progress is byte-based, bounded and committing is not cancellable',
    () {
      BackupProgress progress(
        BackupStage stage, {
        int? total = 100,
        int done = 65,
      }) => BackupProgress(
        taskId: 'task',
        sequence: 1,
        operation: BackupOperation.export,
        stage: stage,
        processedBytes: done,
        totalBytes: total,
        processedRecordings: 1,
      );
      expect(progress(BackupStage.packing).fraction, .65);
      expect(progress(BackupStage.saving, total: null).fraction, isNull);
      expect(progress(BackupStage.committing).canCancel, isFalse);
      expect(progress(BackupStage.completed).canCancel, isFalse);
      expect(progress(BackupStage.awaitingConfirmation).canCancel, isTrue);
      expect(
        () => progress(BackupStage.packing, done: 101),
        throwsArgumentError,
      );
    },
  );
}
