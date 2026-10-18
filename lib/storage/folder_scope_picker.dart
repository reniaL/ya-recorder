import 'package:flutter/material.dart';

import '../l10n/localization.dart';
import 'models/recording_folder.dart';
import 'recording_store.dart';

/// Shows the current library scopes in a compact, scrollable inline card.
class FolderScopePicker extends StatefulWidget {
  const FolderScopePicker({
    super.key,
    required this.store,
    this.selectedId,
    this.onSelected,
    this.expanded = true,
  });

  final RecordingStore store;
  final String? selectedId;
  final ValueChanged<String?>? onSelected;
  final bool expanded;

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

  @override
  void didUpdateWidget(covariant FolderScopePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.coordinator.removeListener(_changed);
      _protected = widget.store.coordinator.isProtected;
      widget.store.coordinator.addListener(_changed);
      _folders = widget.store.listFolders();
    }
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: widget.expanded
          ? Card(
              key: const Key('folderScopeOptionsCard'),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              clipBehavior: Clip.antiAlias,
              color: colors.surfaceContainerLow,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colors.outlineVariant),
              ),
              child: FutureBuilder<List<RecordingFolder>>(
                future: _folders,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n(context).foldersReadFailed),
                          TextButton(
                            onPressed: () => setState(() {
                              _folders = widget.store.listFolders();
                            }),
                            child: Text(l10n(context).retry),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final folders = snapshot.data!;
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        _scopeTile(
                          context,
                          id: null,
                          title: l10n(context).allRecordings,
                          icon: Icons.library_music_outlined,
                        ),
                        for (final folder in folders)
                          _scopeTile(
                            context,
                            id: folder.id,
                            title: folder.name,
                            icon: Icons.folder_outlined,
                          ),
                      ],
                    ),
                  );
                },
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  Widget _scopeTile(
    BuildContext context, {
    required String? id,
    required String title,
    required IconData icon,
  }) {
    final selected = widget.selectedId == id;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: ListTile(
        key: Key('folderScope-${id ?? 'all'}'),
        dense: true,
        leading: Icon(icon, color: selected ? colors.primary : null),
        title: Text(title),
        selected: selected,
        trailing: selected
            ? Icon(Icons.check_circle_rounded, color: colors.primary)
            : null,
        onTap: widget.onSelected == null ? null : () => widget.onSelected!(id),
      ),
    );
  }
}
