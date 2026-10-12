import 'package:flutter_test/flutter_test.dart';

import '../../tools/aac-adts/probe_checks.dart';

void main() {
  Map<String, dynamic> measured() => {
    'container': 'adts',
    'codec': 'aac',
    'profile': 'LC',
    'fullDecode': true,
    'decodedDurationMs': 8100,
    'activeCaptureMs': 8050,
    'playerDurationMs': 8400,
    'seeks': [
      {'targetMs': 4000, 'reportedMs': 4100},
    ],
    'speeds': [
      {'speed': 2.0, 'wallMs': 1000, 'advancedMs': 1950},
    ],
    'completedPlayback': true,
  };

  test('accepts small duration estimates and reported seek differences', () {
    expect(evaluateProbe(measured()), isEmpty);
  });

  test('detects recording that includes the two-second pause', () {
    final report = measured()..['decodedDurationMs'] = 10100;
    expect(evaluateProbe(report), contains('解码时长与有效录音时长相差超过 500 ms'));
  });

  test('does not treat unknown playback duration as a pass', () {
    final report = measured()..['playerDurationMs'] = null;
    expect(evaluateProbe(report), contains('播放器时长缺失或与解码时长相差超过 1000 ms'));
  });

  test('detects stuck seeking, ineffective speed and incomplete playback', () {
    final report = measured()
      ..['seeks'] = [
        {'targetMs': 4000, 'reportedMs': 0},
      ]
      ..['speeds'] = [
        {'speed': 2.0, 'wallMs': 1000, 'advancedMs': 1000},
      ]
      ..['completedPlayback'] = false;
    expect(evaluateProbe(report), hasLength(3));
  });

  test('rejects wrong container or a missing full decode', () {
    final report = measured()
      ..['container'] = 'mp4'
      ..['fullDecode'] = false;
    expect(evaluateProbe(report), contains('文件未通过 ADTS / AAC-LC 完整解码'));
  });
}
