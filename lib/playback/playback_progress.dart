import 'dart:async';

import 'package:flutter/material.dart';

import '../storage/models/recording.dart';
import 'audio_playback_service.dart';

/// Keeps finger-driven updates local instead of waiting for native seeks.
class PlaybackProgress extends StatefulWidget {
  const PlaybackProgress({
    super.key,
    required this.recording,
    required this.service,
    this.sliderKey,
    this.trailing,
  });

  final Recording recording;
  final AudioPlaybackService service;
  final Key? sliderKey;
  final Widget? trailing;

  @override
  State<PlaybackProgress> createState() => _PlaybackProgressState();
}

class _PlaybackProgressState extends State<PlaybackProgress> {
  PlaybackScrubSession? _session;
  double? _preview;
  bool _committing = false;

  void _start(double value) {
    final session = widget.service.beginScrub();
    if (session == null) return;
    setState(() {
      _session = session;
      _preview = value;
    });
  }

  void _change(double value) {
    if (_session == null || !widget.service.isCurrentScrub(_session!)) return;
    setState(() => _preview = value);
  }

  Future<void> _end(double value) async {
    final session = _session;
    if (session == null) return;
    setState(() {
      _preview = value;
      _committing = true;
    });
    try {
      await widget.service.finishScrub(
        session,
        Duration(milliseconds: value.round()),
      );
    } finally {
      if (mounted && identical(_session, session)) {
        setState(() {
          _session = null;
          _preview = null;
          _committing = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(PlaybackProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.recording.id != widget.recording.id) {
      if (_session != null) oldWidget.service.cancelScrub(_session!);
      _session = null;
      _preview = null;
      _committing = false;
    }
  }

  @override
  void dispose() {
    if (_session != null) widget.service.cancelScrub(_session!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackStatus>(
      stream: widget.service.statuses,
      initialData: widget.service.status,
      builder: (context, snapshot) {
        // Read the current status even before the stream delivers a queued event.
        final status = widget.service.status;
        final total = widget.recording.duration;
        final active = status.recordingId == widget.recording.id;
        final previewing =
            _session != null && widget.service.isCurrentScrub(_session!);
        final value =
            (previewing
                    ? _preview!
                    : active
                    ? status.position.inMilliseconds.toDouble()
                    : 0.0)
                .clamp(0.0, total.inMilliseconds.toDouble());
        final enabled =
            active &&
            total > Duration.zero &&
            status.state != PlaybackState.loading &&
            status.state != PlaybackState.failed &&
            !_committing &&
            (!widget.service.isScrubbing || previewing);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: '播放进度',
              child: Slider(
                key: widget.sliderKey,
                value: value,
                max: total.inMilliseconds > 0
                    ? total.inMilliseconds.toDouble()
                    : 1,
                onChangeStart: enabled ? _start : null,
                onChanged: enabled ? _change : null,
                onChangeEnd: enabled ? (value) => unawaited(_end(value)) : null,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(_format(Duration(milliseconds: value.round()))),
                ),
                Text(_format(total)),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ],
        );
      },
    );
  }

  String _format(Duration duration) {
    final seconds = duration.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
