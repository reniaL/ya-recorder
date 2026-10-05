import 'dart:async';

import 'package:flutter/material.dart';

import '../storage/models/recording.dart';
import 'audio_playback_service.dart';

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
        appBar: AppBar(title: const Text('录音详情')),
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
              final position = active
                  ? Duration(
                      milliseconds: status.position.inMilliseconds.clamp(
                        0,
                        total.inMilliseconds,
                      ),
                    )
                  : Duration.zero;
              final createdAt = widget.recording.createdAt.toLocal();
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.recording.title,
                      key: const Key('recordingDetailTitle'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${createdAt.year}-${_twoDigits(createdAt.month)}-${_twoDigits(createdAt.day)} '
                      '${_twoDigits(createdAt.hour)}:${_twoDigits(createdAt.minute)}',
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
                    const SizedBox(height: 16),
                    Semantics(
                      label: '播放进度',
                      child: Slider(
                        key: const Key('recordingDetailProgress'),
                        value: position.inMilliseconds.toDouble(),
                        max: total.inMilliseconds > 0
                            ? total.inMilliseconds.toDouble()
                            : 1,
                        onChanged: active && !loading && !failed
                            ? (value) => widget.playbackService.seek(
                                Duration(milliseconds: value.round()),
                              )
                            : null,
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 16,
                      children: [
                        Text(_formatDuration(position)),
                        Text(_formatDuration(total)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: IconButton.filled(
                        key: const Key('recordingDetailPlayButton'),
                        tooltip: playing ? '暂停播放' : '播放录音',
                        iconSize: 48,
                        onPressed: loading || failed
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

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${_twoDigits(seconds % 60)}';
  }
}
