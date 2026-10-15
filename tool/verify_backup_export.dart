// Independent protocol verification for generated test/device export artifacts.
// Not an untrusted-ZIP import adapter; BKP-05 must bound directory parsing first.
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:ya_recorder/backup/backup_contract.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/verify_backup_export.dart <export.zip> ...',
    );
    exitCode = 64;
    return;
  }
  for (final path in arguments) {
    final input = InputFileStream(path);
    try {
      final decoder = ZipDecoder();
      decoder.decodeStream(input);
      final headers = decoder.directory.fileHeaders;
      final entries = [
        for (final h in headers)
          BackupEntry(
            path: h.filename,
            size: h.uncompressedSize,
            isFile: !h.filename.endsWith('/'),
            isSymbolicLink: (h.externalFileAttributes >> 16) & 0xf000 == 0xa000,
            isEncrypted: h.file!.flags & 1 != 0,
            compressionMethod: h.file!.compressionMethod == CompressionType.none
                ? 0
                : -1,
          ),
      ];
      List<int> jsonBytes(String name) {
        final header = headers.singleWhere((h) => h.filename == name);
        if (header.uncompressedSize > const BackupLimits().maxJsonBytes) {
          throw StateError('Oversized JSON');
        }
        return header.file!.getStream(decompress: false).toUint8List();
      }

      const contract = BackupContract();
      final document = contract.parse(
        manifestBytes: jsonBytes('manifest.json'),
        metadataBytes: jsonBytes('metadata.json'),
        entries: entries,
      );
      for (final file in document.files) {
        final stream = headers
            .singleWhere((h) => h.filename == file.path)
            .file!
            .getStream(decompress: false);
        Stream<List<int>> chunks() async* {
          while (!stream.isEOS) {
            yield stream
                .readBytes(stream.length < 65536 ? stream.length : 65536)
                .toUint8List();
          }
        }

        await contract.verifyContent(file, chunks());
      }
      stdout.writeln(
        '$path: v1 valid; ${document.recordings.length} recordings, ${document.folders.length} folders; all SHA-256 values verified',
      );
    } finally {
      await input.close();
    }
  }
}
