/// Evaluate measured device results. A passing reported seek is not proof of
/// sample-accurate audible positioning; the listening check remains separate.
List<String> evaluateProbe(Map<String, dynamic> report) {
  final failures = <String>[];
  if (report['container'] != 'adts' ||
      report['codec'] != 'aac' ||
      report['profile'] != 'LC' ||
      report['fullDecode'] != true) {
    failures.add('文件未通过 ADTS / AAC-LC 完整解码');
  }
  final decoded = (report['decodedDurationMs'] as num).toInt();
  final active = (report['activeCaptureMs'] as num).toInt();
  if ((decoded - active).abs() > 500) {
    failures.add('解码时长与有效录音时长相差超过 500 ms');
  }
  final playerDuration = report['playerDurationMs'] as num?;
  if (playerDuration == null || (playerDuration - decoded).abs() > 1000) {
    failures.add('播放器时长缺失或与解码时长相差超过 1000 ms');
  }
  for (final seek in report['seeks'] as List<dynamic>) {
    final item = seek as Map<String, dynamic>;
    if (((item['reportedMs'] as num) - (item['targetMs'] as num)).abs() > 500) {
      failures.add('播放器未到达请求位置：${item['targetMs']} ms');
    }
  }
  for (final speed in report['speeds'] as List<dynamic>) {
    final item = speed as Map<String, dynamic>;
    final expected = (item['speed'] as num) * (item['wallMs'] as num);
    if (((item['advancedMs'] as num) - expected).abs() > 500) {
      failures.add('倍速进度不符：${item['speed']}×');
    }
  }
  if (report['completedPlayback'] != true) {
    failures.add('未播放到文件末尾');
  }
  return failures;
}
