import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/recording/recording_service.dart';
import 'package:ya_recorder/settings/recording_settings_page.dart';
import 'package:ya_recorder/storage/recording_store.dart';

void main() {
  late _Store store;
  late _Service service;
  setUp(() {
    store = _Store();
    service = _Service();
  });

  Future<void> open(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: RecordingSettingsPage(store: store, service: service),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('defaultRecordingFormat')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'choosing MP3 persists immediately; reopening reads the preference',
    (tester) async {
      await open(tester);
      expect(find.text('M4A'), findsOneWidget);
      expect(find.text('用于下一次录音，已有录音保持原格式'), findsOneWidget);
      await choose(tester);
      await tester.tap(find.byKey(const Key('chooseFormat-mp3')));
      await tester.pumpAndSettle();
      expect(store.format, RecordingFormat.mp3);
      expect(store.writes, 1);
      expect(find.text('MP3'), findsOneWidget);
      expect(find.byKey(const Key('chooseFormat-mp3')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(find.text('MP3'), findsOneWidget);
    },
  );

  testWidgets(
    'native gate disables MP3 while preserving an existing MP3 preference',
    (tester) async {
      service.available = [RecordingFormat.m4a];
      store.format = RecordingFormat.mp3;
      await open(tester);
      expect(find.text('MP3'), findsOneWidget);
      await choose(tester);
      final mp3 = find.byKey(const Key('chooseFormat-mp3'));
      expect(tester.widget<ListTile>(mp3).enabled, isFalse);
      expect(find.text('MP3 暂不可用'), findsOneWidget);
      await tester.tap(mp3);
      await tester.pumpAndSettle();
      expect(store.writes, 0);
      await tester.tap(find.byKey(const Key('chooseFormat-m4a')));
      await tester.pumpAndSettle();
      expect(store.format, RecordingFormat.m4a);
    },
  );

  testWidgets('save failure retains original selection and permits retry', (
    tester,
  ) async {
    store.failWrite = true;
    await open(tester);
    await choose(tester);
    await tester.tap(find.byKey(const Key('chooseFormat-mp3')));
    await tester.pumpAndSettle();
    expect(find.text('无法保存录音格式，请重试。'), findsOneWidget);
    expect(store.format, RecordingFormat.m4a);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const Key('chooseFormat-m4a'))),
      matchesSemantics(
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        isButton: true,
        hasSelectedState: true,
        label: 'M4A',
      ),
    );
    semantics.dispose();
    store.failWrite = false;
    await tester.tap(find.byKey(const Key('chooseFormat-mp3')));
    await tester.pumpAndSettle();
    expect(store.format, RecordingFormat.mp3);
    expect(store.writes, 2);
  });

  testWidgets('pending save blocks duplicate writes, dismissal and back', (
    tester,
  ) async {
    final gate = Completer<void>();
    store.writeGate = gate.future;
    await open(tester);
    await choose(tester);
    await tester.tap(find.byKey(const Key('chooseFormat-mp3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('chooseFormat-m4a')));
    await tester.tap(find.text('取消'));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(store.writes, 1);
    expect(store.format, RecordingFormat.m4a);
    expect(find.text('正在保存'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(store.format, RecordingFormat.mp3);
    expect(find.byKey(const Key('chooseFormat-mp3')), findsNothing);
  });

  testWidgets('cancel, back and current selection do not write', (
    tester,
  ) async {
    await open(tester);
    await choose(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await choose(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await choose(tester);
    await tester.tap(find.byKey(const Key('chooseFormat-m4a')));
    await tester.pumpAndSettle();
    expect(store.writes, 0);
  });

  testWidgets('read failure offers retry without a false default value', (
    tester,
  ) async {
    store.failRead = true;
    await open(tester);
    expect(find.text('无法读取录音格式设置，请重试。'), findsOneWidget);
    expect(find.byKey(const Key('defaultRecordingFormat')), findsNothing);
    store.failRead = false;
    store.format = RecordingFormat.mp3;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('MP3'), findsOneWidget);
  });

  testWidgets('capability failure keeps choices unavailable until retry', (
    tester,
  ) async {
    service.failRead = true;
    await open(tester);
    expect(find.byKey(const Key('defaultRecordingFormat')), findsNothing);
    service.failRead = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await choose(tester);
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('chooseFormat-mp3')))
          .enabled,
      isTrue,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'narrow large text $brightness keeps formats readable and accessible',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (_, child) => MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(2),
              ),
              child: child!,
            ),
            home: RecordingSettingsPage(store: store, service: service),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(find.byKey(const Key('defaultRecordingFormat')))
              .value,
          'M4A',
        );
        await choose(tester);
        for (final format in RecordingFormat.values) {
          final row = find.byKey(Key('chooseFormat-${format.wireName}'));
          expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
          expect(tester.getSemantics(row).label, format.label);
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('chooseFormat-mp3')));
        await tester.pumpAndSettle();
        expect(find.text('MP3'), findsOneWidget);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}

class _Store extends RecordingStore {
  _Store() : super(databasePath: 'unused', databaseFactory: databaseFactoryFfi);
  RecordingFormat format = RecordingFormat.m4a;
  bool failRead = false;
  bool failWrite = false;
  int writes = 0;
  Future<void>? writeGate;

  @override
  Future<RecordingFormat> getDefaultRecordingFormat() async {
    if (failRead) throw StateError('read failed');
    return format;
  }

  @override
  Future<void> setDefaultRecordingFormat(RecordingFormat value) async {
    writes++;
    if (writeGate != null) await writeGate;
    if (failWrite) throw StateError('write failed');
    format = value;
  }
}

class _Service extends RecordingService {
  List<RecordingFormat> available = RecordingFormat.values;
  bool failRead = false;
  @override
  Future<List<RecordingFormat>> getAvailableFormats() async {
    if (failRead) throw StateError('capability unavailable');
    return available;
  }
}
