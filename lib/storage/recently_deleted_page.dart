import 'package:flutter/material.dart';

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
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final now = _now;
      final failures = await widget.store.purgeExpiredRecordings(now: now);
      final recordings = await widget.store.listRecentlyDeleted();
      if (!mounted) return;
      setState(() {
        _recordings = recordings
            .where(
              (r) =>
                  r.deletedAt!.add(RecordingStore.retentionPeriod).isAfter(now),
            )
            .toList();
        _error = failures.isEmpty ? null : '部分过期录音未能清理，请重试。';
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取最近删除，请重试。');
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
          builder: (context) => AlertDialog(
            title: const Text('永久删除录音？'),
            content: Text('“${recording.title}”的音频文件将被永久删除，无法恢复。'),
            actions: [
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('永久删除'),
              ),
            ],
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
          SnackBar(content: Text(permanently ? '录音已永久删除' : '录音已恢复')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = permanently ? '永久删除失败，录音仍保留在最近删除中，请重试。' : '恢复失败，请重试。',
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
    return '删除于 $date\n剩余 $remaining 天';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('最近删除')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('删除的录音保留 30 天，过期后自动清理。恢复时放回原文件夹；文件夹已删除时放回全部录音。'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _busy ? null : _load,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: _recordings.isEmpty
                  ? Center(child: Text(_busy ? '正在读取最近删除…' : '最近删除为空'))
                  : RefreshIndicator(
                      onRefresh: () async {
                        if (!_busy) await _load();
                      },
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
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
                              enabled: !_busy,
                              tooltip: '${recording.title}的操作',
                              onSelected: (action) => _apply(
                                recording,
                                permanently: action == 'delete',
                              ),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'restore',
                                  child: Text('恢复'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('永久删除'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
