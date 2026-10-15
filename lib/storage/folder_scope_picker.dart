import 'package:flutter/material.dart';

import '../l10n/localization.dart';
import 'models/recording_folder.dart';
import 'recording_store.dart';

/// Browsing remains available during backup. Refresh once on task release,
/// including while this sheet is open, rather than on every progress tick.
class FolderScopePicker extends StatefulWidget {
  const FolderScopePicker({super.key, required this.store, this.selectedId});
  final RecordingStore store;
  final String? selectedId;
  @override
  State<FolderScopePicker> createState() => _FolderScopePickerState();
}

class _FolderScopePickerState extends State<FolderScopePicker> {
  late Future<List<RecordingFolder>> _folders = widget.store.listFolders();
  late bool _protected;
  @override
  void initState() {
    super.initState();
    _protected = widget.store.coordinator.isProtected;
    widget.store.coordinator.addListener(_changed);
  }

  void _changed() {
    final next = widget.store.coordinator.isProtected;
    if (next == _protected || !mounted) return;
    _protected = next;
    if (!next) {
      setState(() {
        _folders = widget.store.listFolders();
      });
    }
  }

  @override
  void dispose() {
    widget.store.coordinator.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FutureBuilder<List<RecordingFolder>>(
      future: _folders,
      builder: (context, snapshot) {
        final folders = snapshot.data ?? [];
        return ListView.builder(
          shrinkWrap: true,
          itemCount: folders.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return ListTile(
                title: Text(
                  snapshot.hasError
                      ? l10n(context).foldersReadFailed
                      : l10n(context).selectScope,
                ),
              );
            }
            final folder = index == 1 ? null : folders[index - 2];
            return ListTile(
              key: Key('folderScope-${folder?.id ?? 'all'}'),
              leading: Icon(
                folder == null
                    ? Icons.library_music_outlined
                    : Icons.folder_outlined,
              ),
              title: Text(folder?.name ?? l10n(context).allRecordings),
              trailing: widget.selectedId == folder?.id
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(context, folder?.id ?? ''),
            );
          },
        );
      },
    ),
  );
}
