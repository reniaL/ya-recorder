import '../theme/app_theme.dart';
import '../l10n/localization.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../storage/models/recording.dart';
import '../widgets/copy_recording_title.dart';
import 'audio_playback_service.dart';
import 'playback_progress.dart';

class RecordingDetailPage extends StatefulWidget {
  const RecordingDetailPage({
    super.key,
    required this.recording,
    required this.playbackService,
    required this.onRename,
    required this.onMove,
    required this.onShare,
    required this.canModify,
  });

  final Recording recording;
  final AudioPlaybackService playbackService;
  final Future<void> Function(Recording, ValueChanged<Recording>) onRename;
  final Future<void> Function(Recording, ValueChanged<Recording>) onMove;
  final Future<void> Function(Recording) onShare;
  final bool canModify;

  @override
  State<RecordingDetailPage> createState() => _RecordingDetailPageState();
}

class _RecordingDetailPageState extends State<RecordingDetailPage> {
  bool _stopped = false;
  bool _changingSpeed = false;
  late Recording _recording = widget.recording;
  bool _actionInProgress = false;

  Future<void> _runRecordingAction(
    Future<void> Function() action, {
    required String errorKey,
  }) async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizedMessage(context, errorKey))),
        );
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _rename() => _runRecordingAction(() async {
    await widget.onRename(_recording, (updated) {
      if (mounted) setState(() => _recording = updated);
    });
  }, errorKey: 'renameRecordingFailed');

  Future<void> _move() => _runRecordingAction(() async {
    await widget.onMove(_recording, (updated) {
      if (mounted) setState(() => _recording = updated);
    });
  }, errorKey: 'moveRecordingFailed');

  Future<void> _share() => _runRecordingAction(
    () => widget.onShare(_recording),
    errorKey: 'shareFailed',
  );

  void _showFullTitle() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n(context).recordingTitle),
        content: SingleChildScrollView(child: SelectableText(_recording.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n(context).close),
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
    unawaited(widget.playbackService.play(_recording));
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
            message: l10n(context).viewFullTitle,
            child: InkWell(
              key: const Key('recordingDetailTitleButton'),
              onTap: _showFullTitle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _recording.title,
                    key: const Key('recordingDetailTitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              constraints: AppMenuStyle.constraints(context),
              key: const Key('recordingDetailActions'),
              tooltip: l10n(context).recordingActions,
              enabled: !_actionInProgress,
              onSelected: (action) {
                if (action == 'copyTitle') {
                  unawaited(copyRecordingTitle(context, _recording.title));
                }
                if (action == 'rename') unawaited(_rename());
                if (action == 'move') unawaited(_move());
                if (action == 'share') unawaited(_share());
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'copyTitle',
                  child: Text(l10n(context).copyTitle),
                ),
                PopupMenuItem(
                  value: 'rename',
                  enabled: widget.canModify,
                  child: Text(l10n(context).rename),
                ),
                PopupMenuItem(
                  value: 'move',
                  enabled: widget.canModify,
                  child: Text(l10n(context).moveToFolder),
                ),
                PopupMenuItem(value: 'share', child: Text(l10n(context).share)),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: StreamBuilder<PlaybackStatus>(
            stream: widget.playbackService.statuses,
            initialData: widget.playbackService.status,
            builder: (context, snapshot) {
              final status = snapshot.data ?? const PlaybackStatus.idle();
              final active = status.recordingId == _recording.id;
              final loading = active && status.state == PlaybackState.loading;
              final failed = active && status.state == PlaybackState.failed;
              final playing = active && status.state == PlaybackState.playing;
              final total = _recording.duration;
              final scrubbing = widget.playbackService.isScrubbing;
              final createdAt = _recording.createdAt.toLocal();
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
                          ? l10n(context).loadingPlayback
                          : failed
                          ? l10n(context).playbackFailed
                          : playing
                          ? l10n(context).playing
                          : active && status.state == PlaybackState.paused
                          ? l10n(context).playbackPaused
                          : l10n(context).notPlaying,
                      key: const Key('recordingDetailState'),
                    ),
                    if (loading) const LinearProgressIndicator(),
                    if (failed) ...[
                      const SizedBox(height: 8),
                      Text(
                        localizedMessage(
                          context,
                          status.errorMessage ?? 'playbackLoadFailed',
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              widget.playbackService.play(_recording),
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n(context).retryPlayback),
                        ),
                      ),
                    ],
                    if (!failed && status.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(localizedMessage(context, status.errorMessage!)),
                    ],
                    const SizedBox(height: 16),
                    PlaybackProgress(
                      recording: _recording,
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
                              tooltip: l10n(context).skipBackward,
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
                              tooltip: playing
                                  ? l10n(context).pausePlayback
                                  : l10n(context).playRecording,
                              iconSize: 48,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(64, 64),
                              ),
                              onPressed: loading || failed || scrubbing
                                  ? null
                                  : () => widget.playbackService.toggle(
                                      _recording,
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
                              tooltip: l10n(context).skipForward,
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
                              icon: const Icon(Icons.forward_10_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        PopupMenuButton<double>(
                          constraints: AppMenuStyle.constraints(context),
                          key: const Key('recordingDetailSpeed'),
                          tooltip: l10n(context).playbackSpeed,
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
                            label: l10n(context).playbackSpeed,
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
