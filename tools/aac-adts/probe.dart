import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'probe_checks.dart';

const probeSourceOptions = ProgressiveAudioSourceOptions(
  androidExtractorOptions: AndroidExtractorOptions(
    constantBitrateSeekingEnabled: true,
  ),
);

void main() {
  if (!kDebugMode) throw UnsupportedError('AAC probe requires a debug build');
  runApp(const MaterialApp(home: AacAdtsProbePage()));
}

class AacAdtsProbePage extends StatefulWidget {
  const AacAdtsProbePage({super.key});

  @override
  State<AacAdtsProbePage> createState() => _AacAdtsProbePageState();
}

class _AacAdtsProbePageState extends State<AacAdtsProbePage> {
  static const channel = MethodChannel('ya_recorder/aac_adts_probe');
  final player = AudioPlayer();
  String phase = '准备就绪';
  Map<String, dynamic>? report;
  bool busy = false;
  String? failure;

  @override
  void initState() {
    super.initState();
    channel.setMethodCallHandler((call) async {
      if (call.method == 'phase' && mounted) {
        setState(() => phase = call.arguments as String);
      }
    });
    if (const bool.fromEnvironment('AAC_PROBE_AUTORUN')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => runProbe());
    }
  }

  Future<void> runProbe() async {
    setState(() {
      busy = true;
      failure = null;
      report = null;
      phase = '请求麦克风权限';
    });
    final measured = <String, dynamic>{
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      'justAudioVersion': '0.10.6',
      'constantBitrateSeekingEnabled': true,
      'listeningCheck': 'pending',
    };
    try {
      await player.stop();
      if (await channel.invokeMethod<bool>('permission') != true) {
        throw StateError('麦克风权限未授予');
      }
      final capture = await channel.invokeMapMethod<String, dynamic>('capture');
      measured.addAll(capture!);
      if (mounted) setState(() => phase = '验证播放器时长、定位及倍速');
      final duration = await player.setAudioSource(
        ProgressiveAudioSource(
          Uri.file(measured['filePath'] as String),
          options: probeSourceOptions,
        ),
      );
      measured['playerDurationMs'] = duration?.inMilliseconds;
      final decodedMs = (measured['decodedDurationMs'] as num).toInt();
      final seeks = <Map<String, dynamic>>[];
      // Includes forward/backward jumps and a near-end seek while paused.
      for (final fraction in [0.0, 0.5, 0.1, 0.9]) {
        final target = (decodedMs * fraction).round();
        await player.seek(Duration(milliseconds: target));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        seeks.add({
          'targetMs': target,
          'reportedMs': player.position.inMilliseconds,
        });
      }
      measured['seeks'] = seeks;
      final speeds = <Map<String, dynamic>>[];
      for (final speed in [0.75, 1.0, 1.25, 1.5, 2.0]) {
        await player.seek(Duration.zero);
        await player.setSpeed(speed);
        // Wait for actual playback before measuring audio-time advancement.
        final started = player.playingStream.firstWhere((value) => value);
        final playback = player.play();
        await Future.any([
          started,
          playback,
        ]).timeout(const Duration(seconds: 5));
        await player.processingStateStream
            .firstWhere((state) => state == ProcessingState.ready)
            .timeout(const Duration(seconds: 5));
        final start = player.position.inMilliseconds;
        final clock = Stopwatch()..start();
        await Future<void>.delayed(const Duration(seconds: 1));
        final advanced = player.position.inMilliseconds - start;
        clock.stop();
        await player.pause();
        await playback;
        speeds.add({
          'speed': speed,
          'wallMs': clock.elapsedMilliseconds,
          'advancedMs': advanced,
        });
      }
      measured['speeds'] = speeds;
      await player.setSpeed(1);
      await player.seek(Duration.zero);
      if (mounted) setState(() => phase = '完整播放：请听暂停前后有无额外静音');
      final completed = player.processingStateStream.firstWhere(
        (state) => state == ProcessingState.completed,
      );
      final playback = player.play();
      await Future.any([
        completed,
        playback,
      ]).timeout(Duration(milliseconds: decodedMs + 10000));
      if (player.processingState != ProcessingState.completed) {
        throw StateError('播放未到达末尾');
      }
      await player.pause();
      measured['completedPlayback'] = true;
      measured['failures'] = evaluateProbe(measured);
      measured['automatedChecksPassed'] =
          (measured['failures'] as List).isEmpty;
    } catch (error) {
      measured['automatedChecksPassed'] = false;
      measured['error'] = error.toString();
      failure = error.toString();
      await player.stop();
    }
    try {
      await channel.invokeMethod<void>('saveReport', jsonEncode(measured));
    } catch (error) {
      failure = '报告保存失败：$error';
    }
    if (!mounted) return;
    setState(() {
      report = measured;
      busy = false;
      phase = '自动检查结束；仍需听音确认定位和暂停连续性';
    });
  }

  Future<void> confirmListening(bool passed) async {
    report!['listeningCheck'] = passed ? 'passed' : 'failed';
    await channel.invokeMethod<void>('saveReport', jsonEncode(report));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    channel.setMethodCallHandler(null);
    unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AAC / ADTS 第一步验证')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '保持此页在前台：录音 4 秒 → 暂停 2 秒 → 续录 4 秒。'
          '请分别说出 1–4 和 5–8。自动检查后可试听、拖动及切换倍速。',
        ),
        const SizedBox(height: 16),
        Text(phase),
        if (failure != null)
          Text(failure!, style: const TextStyle(color: Colors.red)),
        FilledButton(
          onPressed: busy ? null : runProbe,
          child: const Text('生成样本并验证'),
        ),
        if (report?['filePath'] != null && !busy) ...[
          StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (context, snapshot) {
              final durationMs = (report!['decodedDurationMs'] as num)
                  .toDouble();
              final position = (snapshot.data ?? Duration.zero).inMilliseconds
                  .toDouble();
              return Slider(
                max: durationMs,
                value: position.clamp(0, durationMs),
                onChanged: (value) =>
                    player.seek(Duration(milliseconds: value.round())),
              );
            },
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () async {
                  if (player.processingState == ProcessingState.completed) {
                    await player.seek(Duration.zero);
                  }
                  unawaited(player.play());
                },
                child: const Text('播放'),
              ),
              TextButton(onPressed: player.pause, child: const Text('暂停')),
              for (final delta in [-5, 5])
                TextButton(
                  onPressed: () {
                    final maxMs = (report!['decodedDurationMs'] as num).toInt();
                    final target =
                        (player.position.inMilliseconds + delta * 1000).clamp(
                          0,
                          maxMs,
                        );
                    player.seek(Duration(milliseconds: target));
                  },
                  child: Text('${delta > 0 ? '+' : ''}$delta 秒'),
                ),
              for (final speed in [0.75, 1.0, 1.25, 1.5, 2.0])
                TextButton(
                  onPressed: () => player.setSpeed(speed),
                  child: Text('$speed×'),
                ),
            ],
          ),
          const Text(
            '听音后确认：暂停处无额外 2 秒静音，拖动/跳转符合数数位置，倍速可听。'
            '播放器报告的位置不代表实际音频定位精度。',
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => confirmListening(true),
                child: const Text('听音通过'),
              ),
              TextButton(
                onPressed: () => confirmListening(false),
                child: const Text('听音失败'),
              ),
            ],
          ),
        ],
        if (report != null)
          SelectableText(const JsonEncoder.withIndent('  ').convert(report)),
      ],
    ),
  );
}
