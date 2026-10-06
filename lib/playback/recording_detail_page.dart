import 'dart:async';

import 'package:flutter/material.dart';

import '../storage/models/recording.dart';
import 'audio_playback_service.dart';
import 'playback_progress.dart';

class RecordingDetailPage extends StatefulWidget {
  const RecordingDetailPage({
    super.key,
    required this.recording,
    required this.playbackService,
  });

  final Recording recording;
  final AudioPlaybackService playbackService;

  @override
  State<RecordingDetailPage> createState() => _RecordingDetailPageState();
}

class _RecordingDetailPageState extends State<RecordingDetailPage> {
  bool _stopped = false;
  bool _changingSpeed = false;

  void _showFullTitle() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('录音标题'),
        content: SingleChildScrollView(
          child: SelectableText(widget.recording.title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _setSpeed(double speed) async {
    if (_changingSpeed) return;
    setState(() => _changingSpeed = true);
    try {
      await widget.playbackService.setSpeed(speed);
    } finally {
      if (mounted) setState(() => _changingSpeed = false);
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(widget.playbackService.play(widget.recording));
  }

  void _stopPlayback() {
    if (_stopped) return;
    _stopped = true;
    unawaited(widget.playbackService.stop());
  }

  @override
  void dispose() {
    _stopPlayback();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _stopPlayback();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Tooltip(
            message: '查看完整录音标题',
            child: InkWell(
              key: const Key('recordingDetailTitleButton'),
              onTap: _showFullTitle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.recording.title,
                    key: const Key('recordingDetailTitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: StreamBuilder<PlaybackStatus>(
            stream: widget.playbackService.statuses,
            initialData: widget.playbackService.status,
            builder: (context, snapshot) {
              final status = snapshot.data ?? const PlaybackStatus.idle();
              final active = status.recordingId == widget.recording.id;
              final loading = active && status.state == PlaybackState.loading;
              final failed = active && status.state == PlaybackState.failed;
              final playing = active && status.state == PlaybackState.playing;
              final total = widget.recording.duration;
              final scrubbing = widget.playbackService.isScrubbing;
              final createdAt = widget.recording.createdAt.toLocal();
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${createdAt.year}-${_twoDigits(createdAt.month)}-${_twoDigits(createdAt.day)} '
                      '${_twoDigits(createdAt.hour)}:${_twoDigits(createdAt.minute)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      loading
                          ? '正在加载'
                          : failed
                          ? '播放失败'
                          : playing
                          ? '正在播放'
                          : active && status.state == PlaybackState.paused
                          ? '已暂停'
                          : '未播放',
                      key: const Key('recordingDetailState'),
                    ),
                    if (loading) const LinearProgressIndicator(),
                    if (failed) ...[
                      const SizedBox(height: 8),
                      Text(status.errorMessage ?? '无法播放该录音。'),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              widget.playbackService.play(widget.recording),
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试播放'),
                        ),
                      ),
                    ],
                    if (!failed && status.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(status.errorMessage!),
                    ],
                    const SizedBox(height: 16),
                    PlaybackProgress(
                      recording: widget.recording,
                      service: widget.playbackService,
                      sliderKey: const Key('recordingDetailProgress'),
                    ),
                    const SizedBox(height: 24),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: const Key('recordingDetailSkipBackward'),
                              tooltip: '快退 5 秒',
                              iconSize: 36,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(56, 56),
                              ),
                              onPressed:
                                  active &&
                                      !loading &&
                                      !failed &&
                                      !scrubbing &&
                                      total > Duration.zero
                                  ? widget.playbackService.skipBackward
                                  : null,
                              icon: const Icon(Icons.replay_5_rounded),
                            ),
                            const SizedBox(width: 24),
                            IconButton.filled(
                              key: const Key('recordingDetailPlayButton'),
                              tooltip: playing ? '暂停播放' : '播放录音',
                              iconSize: 48,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(64, 64),
                              ),
                              onPressed: loading || failed || scrubbing
                                  ? null
                                  : () => widget.playbackService.toggle(
                                      widget.recording,
                                    ),
                              icon: Icon(
                                playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                            const SizedBox(width: 24),
                            IconButton(
                              key: const Key('recordingDetailSkipForward'),
                              tooltip: '快进 5 秒',
                              iconSize: 36,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(56, 56),
                              ),
                              onPressed:
                                  active &&
                                      !loading &&
                                      !failed &&
                                      !scrubbing &&
                                      total > Duration.zero
                                  ? widget.playbackService.skipForward
                                  : null,
                              icon: const Icon(Icons.forward_5_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        PopupMenuButton<double>(
                          key: const Key('recordingDetailSpeed'),
                          tooltip: '播放倍速',
                          initialValue: active ? status.speed : 1,
                          enabled:
                              active &&
                              !loading &&
                              !failed &&
                              !scrubbing &&
                              !_changingSpeed,
                          onSelected: _setSpeed,
                          itemBuilder: (context) => [
                            for (final speed
                                in AudioPlaybackService.supportedSpeeds)
                              CheckedPopupMenuItem<double>(
                                value: speed,
                                checked: speed == (active ? status.speed : 1),
                                child: Text(_formatSpeed(speed)),
                              ),
                          ],
                          child: Semantics(
                            button: true,
                            label: '播放倍速',
                            value: _formatSpeed(active ? status.speed : 1),
                            excludeSemantics: true,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 64,
                                minHeight: 56,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _formatSpeed(active ? status.speed : 1),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.arrow_drop_down, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _formatSpeed(double speed) =>
      '${speed == speed.roundToDouble() ? speed.toInt() : speed}×';
}
