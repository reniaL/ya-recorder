import 'package:flutter/material.dart';

import '../l10n/localization.dart';
import '../storage/models/recording.dart';

class RenameRecordingDialog extends StatefulWidget {
  const RenameRecordingDialog({
    super.key,
    required this.recording,
    required this.recentRecordings,
  });

  final Recording recording;
  final Future<List<Recording>> recentRecordings;

  @override
  State<RenameRecordingDialog> createState() => _RenameRecordingDialogState();
}

class _RenameRecordingDialogState extends State<RenameRecordingDialog> {
  late final _controller = TextEditingController(text: widget.recording.title);
  final _focusNode = FocusNode();

  List<String> _recentTitles(List<Recording> recordings) {
    final candidates =
        recordings
            .where((r) => r.id != widget.recording.id && !r.isDeleted)
            .toList()
          ..sort((a, b) {
            final aSameFolder = a.folderId == widget.recording.folderId;
            final bSameFolder = b.folderId == widget.recording.folderId;
            if (aSameFolder != bSameFolder) return aSameFolder ? -1 : 1;
            final byDate = b.createdAt.compareTo(a.createdAt);
            return byDate != 0 ? byDate : b.id.compareTo(a.id);
          });
    final titles = <String>{};
    for (final candidate in candidates) {
      final title = candidate.title.trim();
      if (title.isNotEmpty && title != widget.recording.title.trim()) {
        titles.add(title);
        if (titles.length == 10) break;
      }
    }
    return titles.toList();
  }

  void _useTitle(String title) {
    _controller.value = TextEditingValue(
      text: title,
      selection: TextSelection.collapsed(offset: title.length),
    );
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = l10n(context);
    return AlertDialog(
      scrollable: true,
      title: Text(strings.renameRecording),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              maxLength: 120,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) => Navigator.pop(context, value),
              decoration: InputDecoration(labelText: strings.recordingTitle),
            ),
            FutureBuilder<List<Recording>>(
              future: widget.recentRecordings,
              builder: (context, snapshot) {
                final titles = _recentTitles(snapshot.data ?? const []);
                if (titles.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      strings.reuseRecentTitle,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    for (final title in titles)
                      TextButton(
                        style: TextButton.styleFrom(
                          alignment: AlignmentDirectional.centerStart,
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () => _useTitle(title),
                        child: Text(title),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(strings.save),
        ),
      ],
    );
  }
}
