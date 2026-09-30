import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'recording/recording_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.recordingService});

  final RecordingService? recordingService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '丫丫录音',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff0b6657),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff2f7f4),
        useMaterial3: true,
      ),
      home: RecordingHomePage(
        recordingService: recordingService ?? RecordingService(),
      ),
    );
  }
}

class RecordingHomePage extends StatefulWidget {
  const RecordingHomePage({super.key, required this.recordingService});

  final RecordingService recordingService;

  @override
  State<RecordingHomePage> createState() => _RecordingHomePageState();
}

class _RecordingHomePageState extends State<RecordingHomePage> {
  static const _idleStatus = RecordingSessionStatus(
    state: RecordingLifecycleState.idle,
    elapsed: Duration.zero,
    canResume: false,
  );

  late final StreamSubscription<RecordingEvent> _eventSubscription;
  RecordingSessionStatus _status = _idleStatus;
  bool _isSubmitting = false;
  String? _permissionMessage;
  String? _serviceError;

  @override
  void initState() {
    super.initState();
    _eventSubscription = widget.recordingService.events.listen(
      _handleRecordingEvent,
      onError: _handleEventError,
    );
    _loadCurrentStatus();
  }

  @override
  void dispose() {
    _eventSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentStatus() async {
    try {
      final status = await widget.recordingService.getStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
      });
    } on PlatformException catch (error) {
      _setServiceError(error.message ?? '无法读取当前录音状态。');
    } on FormatException catch (error) {
      _setServiceError(error.message);
    }
  }

  Future<void> _requestPermissionAndStart() async {
    if (_isSubmitting || !_canStart) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _permissionMessage = null;
      _serviceError = null;
    });

    try {
      final granted = await widget.recordingService
          .requestMicrophonePermission();
      if (!mounted) {
        return;
      }
      if (!granted) {
        setState(() {
          _permissionMessage = '需要麦克风权限才能开始录音。';
        });
        return;
      }

      setState(() {
        _status = const RecordingSessionStatus(
          state: RecordingLifecycleState.preparing,
          elapsed: Duration.zero,
          canResume: false,
        );
      });
      await widget.recordingService.start();
    } on PlatformException catch (error) {
      _setServiceError(error.message ?? '无法开始录音。');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _openAppSettings() async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serviceError = null;
    });
    try {
      await widget.recordingService.openAppSettings();
    } on PlatformException catch (error) {
      _setServiceError(error.message ?? '无法打开系统设置。');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _pauseOrResume() async {
    if (_isSubmitting || (!_canPause && !_canResume)) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serviceError = null;
    });
    try {
      if (_canPause) {
        await widget.recordingService.pause();
      } else {
        await widget.recordingService.resume();
      }
    } on PlatformException catch (error) {
      _setServiceError(error.message ?? '无法更新录音状态。');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _confirmCancellation() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('放弃这次录音？'),
          content: const Text('当前未保存的内容将被删除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续录音'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放弃'),
            ),
          ],
        );
      },
    );
    if (shouldCancel != true || !mounted) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serviceError = null;
    });
    try {
      await widget.recordingService.cancel();
    } on PlatformException catch (error) {
      _setServiceError(error.message ?? '无法放弃当前录音。');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _handleRecordingEvent(RecordingEvent event) {
    if (!mounted) {
      return;
    }

    switch (event) {
      case RecordingStateChanged(:final status):
        setState(() {
          _status = status;
          if (status.state != RecordingLifecycleState.failed) {
            _serviceError = null;
          }
        });
      case RecordingSaved():
        setState(() {
          _status = _idleStatus;
        });
      case RecordingFailed(:final message):
        setState(() {
          _serviceError = message;
        });
    }
  }

  void _handleEventError(Object error, StackTrace stackTrace) {
    _setServiceError('无法连接录音服务。');
  }

  void _setServiceError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _serviceError = message;
    });
  }

  bool get _canStart =>
      _status.state == RecordingLifecycleState.idle ||
      _status.state == RecordingLifecycleState.failed;

  bool get _hasActiveSession => switch (_status.state) {
    RecordingLifecycleState.preparing ||
    RecordingLifecycleState.recording ||
    RecordingLifecycleState.paused ||
    RecordingLifecycleState.discarding ||
    RecordingLifecycleState.stopping => true,
    RecordingLifecycleState.idle || RecordingLifecycleState.failed => false,
  };

  bool get _canPause => _status.state == RecordingLifecycleState.recording;

  bool get _canResume =>
      _status.state == RecordingLifecycleState.paused && _status.canResume;

  bool get _canCancel => switch (_status.state) {
    RecordingLifecycleState.preparing ||
    RecordingLifecycleState.recording ||
    RecordingLifecycleState.paused => true,
    RecordingLifecycleState.idle ||
    RecordingLifecycleState.stopping ||
    RecordingLifecycleState.discarding ||
    RecordingLifecycleState.failed => false,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('丫丫录音'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('新的录音', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                _statusLabel,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    Text(
                      _formatDuration(_status.elapsed),
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Icon(
                      _hasActiveSession
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
                      size: 52,
                      color: _hasActiveSession
                          ? const Color(0xffd5543f)
                          : colorScheme.primary,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_permissionMessage != null) ...[
                _MessagePanel(
                  icon: Icons.mic_off_rounded,
                  message: _permissionMessage!,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _isSubmitting ? null : _openAppSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('前往系统设置'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_serviceError != null) ...[
                _MessagePanel(
                  icon: Icons.error_outline_rounded,
                  message: _serviceError!,
                  isError: true,
                ),
                const SizedBox(height: 16),
              ],
              if (_canStart)
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting
                        ? null
                        : _requestPermissionAndStart,
                    icon: const Icon(Icons.mic_rounded),
                    label: Text(_permissionMessage == null ? '开始录音' : '再次请求'),
                  ),
                )
              else if (_canPause || _canResume || _canCancel)
                Row(
                  children: [
                    if (_canPause || _canResume)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isSubmitting ? null : _pauseOrResume,
                          icon: Icon(
                            _canPause
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          label: Text(_canPause ? '暂停' : '继续录音'),
                        ),
                      ),
                    if ((_canPause || _canResume) && _canCancel)
                      const SizedBox(width: 12),
                    if (_canCancel)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSubmitting
                              ? null
                              : _confirmCancellation,
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('放弃本次录音'),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _statusLabel => switch (_status.state) {
    RecordingLifecycleState.idle => '准备好后即可开始录音',
    RecordingLifecycleState.preparing => '正在准备录音',
    RecordingLifecycleState.recording => '正在录音',
    RecordingLifecycleState.paused => '录音已暂停',
    RecordingLifecycleState.stopping => '正在完成录音',
    RecordingLifecycleState.discarding => '正在放弃录音',
    RecordingLifecycleState.failed => '录音服务需要重新开始',
  };

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final paddedMinutes = minutes.toString().padLeft(2, '0');
    final paddedSeconds = seconds.toString().padLeft(2, '0');
    if (hours == 0) {
      return '$paddedMinutes:$paddedSeconds';
    }
    return '${hours.toString().padLeft(2, '0')}:$paddedMinutes:$paddedSeconds';
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = isError ? colorScheme.error : colorScheme.onSurface;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isError
            ? colorScheme.errorContainer
            : colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: foregroundColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: foregroundColor)),
            ),
          ],
        ),
      ),
    );
  }
}
