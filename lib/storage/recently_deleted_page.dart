import '../theme/app_theme.dart';
import '../l10n/localization.dart';
import 'package:flutter/material.dart';
import '../widgets/destructive_confirmation_dialog.dart';
import '../backup/backup_page.dart';

import 'models/recording.dart';
import 'recording_store.dart';

class RecentlyDeletedPage extends StatefulWidget {
  const RecentlyDeletedPage({super.key, required this.store, this.now});

  final RecordingStore store;
  final DateTime Function()? now;

  @override
  State<RecentlyDeletedPage> createState() => _RecentlyDeletedPageState();
}

class _RecentlyDeletedPageState extends State<RecentlyDeletedPage>
    with WidgetsBindingObserver {
  List<Recording> _recordings = [];
  bool _busy = true;
  String? _error;

  DateTime get _now => (widget.now?.call() ?? DateTime.now()).toUtc();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.coordinator.addListener(_protectionChanged);
    _wasProtected = widget.store.coordinator.isProtected;
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.coordinator.removeListener(_protectionChanged);
    super.dispose();
  }

  bool _wasProtected = false;
  void _protectionChanged() {
    if (!mounted || _wasProtected == widget.store.coordinator.isProtected) {
      return;
    }
    _wasProtected = widget.store.coordinator.isProtected;
    setState(() {});
    if (!_wasProtected && !_busy) _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final now = _now;
      final failures = widget.store.coordinator.isProtected
          ? <String>[]
          : await widget.store.purgeExpiredRecordings(now: now);
      final recordings = await widget.store.listRecentlyDeleted();
      if (!mounted) return;
      setState(() {
        _recordings = recordings
            .where(
              (r) =>
                  r.deletedAt!.add(RecordingStore.retentionPeriod).isAfter(now),
            )
            .toList();
        _error = failures.isEmpty ? null : 'expiredCleanupRetry';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'deletedReadFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(Recording recording, {required bool permanently}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (permanently) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => DestructiveConfirmationDialog(
            title: l10n(context).permanentDeleteTitle,
            message: l10n(context).permanentDeleteDescription(recording.title),
            actionLabel: l10n(context).permanentDelete,
            onConfirm: () => Navigator.pop(context, true),
          ),
        );
        if (confirmed != true || !mounted) return;
        await widget.store.permanentlyDeleteRecording(recording.id);
      } else {
        // Refresh the retention boundary before restoring a stale page row.
        await widget.store.purgeExpiredRecordings(now: _now);
        if (!recording.deletedAt!
            .add(RecordingStore.retentionPeriod)
            .isAfter(_now)) {
          await _load();
          return;
        }
        await widget.store.restoreRecording(recording.id, now: _now);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Builder(
              builder: (context) => Text(
                localizedMessage(
                  context,
                  permanently
                      ? 'recordingPermanentlyDeleted'
                      : 'recordingRestored',
                ),
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = permanently ? 'permanentDeleteFailed' : 'restoreFailed',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _deletionInfo(Recording recording) {
    final deleted = recording.deletedAt!.toLocal();
    final days = recording.deletedAt!
        .add(RecordingStore.retentionPeriod)
        .difference(_now)
        .inSeconds;
    final remaining = (days / Duration.secondsPerDay).ceil().clamp(0, 30);
    final date =
        '${deleted.year}-${deleted.month.toString().padLeft(2, '0')}-'
        '${deleted.day.toString().padLeft(2, '0')} '
        '${deleted.hour.toString().padLeft(2, '0')}:'
        '${deleted.minute.toString().padLeft(2, '0')}';
    return l10n(context).deletionInfo(date, remaining);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(l10n(context).recentlyDeleted)),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            if (!_busy) await _load();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (widget.store.coordinator.isProtected)
                const SliverToBoxAdapter(child: BackupProtectionNotice()),
              if (_recordings.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l10n(context).deletedDescription),
                  ),
                ),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        Text(localizedMessage(context, _error!)),
                        TextButton(
                          onPressed: _busy ? null : _load,
                          child: Text(l10n(context).retry),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_busy)
                const SliverToBoxAdapter(child: LinearProgressIndicator()),
              if (_recordings.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: _busy
                        ? Text(l10n(context).loadingDeleted)
                        : _error != null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              key: const Key('deletedEmptyState'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  size: 48,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  l10n(context).deletedEmpty,
                                  style: Theme.of(context).textTheme.titleLarge,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n(context).deletedRetentionHint,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () => showDialog<void>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      scrollable: true,
                                      title: Text(
                                        l10n(context).deletedRecoveryRules,
                                      ),
                                      content: Text(
                                        l10n(context).deletedDescription,
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: Text(l10n(context).close),
                                        ),
                                      ],
                                    ),
                                  ),
                                  child: Text(
                                    l10n(context).deletedRecoveryRules,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: _recordings.length,
                  itemBuilder: (context, index) {
                    final recording = _recordings[index];
                    return ListTile(
                      key: Key('deleted-${recording.id}'),
                      title: Text(
                        recording.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_deletionInfo(recording)),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        constraints: AppMenuStyle.constraints(context),
                        enabled:
                            !_busy && !widget.store.coordinator.isProtected,
                        tooltip: l10n(context).titleActions(recording.title),
                        onSelected: (action) =>
                            _apply(recording, permanently: action == 'delete'),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'restore',
                            child: Text(l10n(context).restore),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              l10n(context).permanentDelete,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
