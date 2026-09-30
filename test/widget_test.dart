import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ya_recorder/main.dart';
import 'package:ya_recorder/recording/recording_service.dart';

void main() {
  const commandChannel = MethodChannel(
    'io.github.renial.ya_recorder/recording_commands',
  );
  const eventChannel = MethodChannel(
    'io.github.renial.ya_recorder/recording_events',
  );

  late bool permissionGranted;
  late List<String> invokedMethods;

  setUp(() {
    permissionGranted = false;
    invokedMethods = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(commandChannel, (call) async {
      invokedMethods.add(call.method);
      switch (call.method) {
        case 'getStatus':
          return {'state': 'idle', 'elapsedMs': 0, 'canResume': false};
        case 'requestMicrophonePermission':
          return permissionGranted;
        case 'start':
        case 'cancel':
        case 'openAppSettings':
          return null;
        default:
          throw PlatformException(code: 'unexpected-method');
      }
    });
    messenger.setMockMethodCallHandler(eventChannel, (call) async {
      if (call.method == 'listen' || call.method == 'cancel') {
        return null;
      }
      throw PlatformException(code: 'unexpected-event-method');
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(commandChannel, null);
    messenger.setMockMethodCallHandler(eventChannel, null);
  });

  testWidgets('denied microphone permission can be requested again', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        recordingService: RecordingService(
          commands: commandChannel,
          events: const EventChannel(
            'io.github.renial.ya_recorder/recording_events',
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('开始录音'));
    await tester.pump();

    expect(find.text('需要麦克风权限才能开始录音。'), findsOneWidget);
    expect(find.text('再次请求'), findsOneWidget);
    expect(invokedMethods, contains('requestMicrophonePermission'));

    await tester.tap(find.text('前往系统设置'));
    await tester.pump();
    expect(invokedMethods, contains('openAppSettings'));

    permissionGranted = true;
    await tester.tap(find.text('再次请求'));
    await tester.pump();

    expect(find.text('正在准备录音'), findsOneWidget);
    expect(invokedMethods, contains('start'));
  });
}
