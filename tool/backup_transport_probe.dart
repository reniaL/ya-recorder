// Run only for BKP-03 device verification:
// flutter run -t tool/backup_transport_probe.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:ya_recorder/backup/backup_document_service.dart';
import 'package:ya_recorder/recording/recording_service.dart';

void main() => runApp(const MaterialApp(home: _Probe()));

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final documents = BackupDocumentService();
  final recording = RecordingService();
  bool busy = false;
  String result =
      'BKP-03 transport only. Output is 4 MiB of zeros, not a backup ZIP. '
      'Use the file picker, background/lock screen, notification and Cancel to verify URI streaming.';

  Future<void> run(bool write) async {
    setState(() => busy = true);
    try {
      await documents.recoverInterruptedTransfer();
      final selected = write
          ? await documents.pickTarget('transport-probe-not-a-backup.zip')
          : await documents.pickSource();
      if (selected == null) return;
      final summary = await documents.copy(
        recordingService: recording,
        document: selected,
        write: write,
        prepareOutput: write
            ? (path) async {
                final file = await File(path).open(mode: FileMode.write);
                try {
                  final chunk = Uint8List(64 * 1024);
                  for (var i = 0; i < 64; i++) {
                    recording.coordinator.activeTask!.checkCancelled();
                    await file.writeFrom(chunk);
                  }
                } finally {
                  await file.close();
                }
              }
            : null,
        consume: (value) async {
          final hash = await sha256
              .bind(File(value.stagedPath).openRead())
              .first;
          return '${selected.displayName}\n${value.processedBytes} bytes\nSHA-256: $hash';
        },
      );
      if (mounted) setState(() => result = summary);
    } catch (error) {
      if (mounted) setState(() => result = '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('BKP-03 URI transport probe')),
    body: AnimatedBuilder(
      animation: recording.coordinator,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SelectableText(result),
          const SizedBox(height: 16),
          Text(
            '${recording.coordinator.progress?.stage.name ?? 'idle'}: '
            '${recording.coordinator.progress?.processedBytes ?? 0} bytes',
          ),
          FilledButton(
            onPressed: busy ? null : () => run(false),
            child: const Text('Read document and hash'),
          ),
          FilledButton(
            onPressed: busy ? null : () => run(true),
            child: const Text('Write 4 MiB transport sample'),
          ),
          OutlinedButton(
            onPressed: recording.coordinator.activeTask == null
                ? null
                : () {
                    recording.coordinator.requestCancel(
                      recording.coordinator.activeTask!,
                    );
                  },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}
