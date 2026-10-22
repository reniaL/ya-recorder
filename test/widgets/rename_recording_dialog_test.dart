import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ya_recorder/l10n/app_localizations.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/storage/models/recording.dart';
import 'package:ya_recorder/widgets/rename_recording_dialog.dart';

Recording recording(
  String id,
  String title, {
  int day = 1,
  String? folder = 'work',
  bool deleted = false,
}) => Recording(
  id: id,
  title: title,
  filePath: '/$id.aac',
  createdAt: DateTime.utc(2026, 10, day),
  duration: const Duration(seconds: 10),
  fileSizeBytes: 1024,
  format: RecordingFormat.aac,
  folderId: folder,
  deletedAt: deleted ? DateTime.utc(2026, 10, 22) : null,
);

Future<void> openDialog(
  WidgetTester tester,
  Future<List<Recording>> recent, {
  ValueChanged<String?>? onResult,
  Locale locale = const Locale('zh'),
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await showDialog<String>(
                context: context,
                builder: (_) => RenameRecordingDialog(
                  recording: recording('current', '新录音', day: 22),
                  recentRecordings: recent,
                ),
              );
              onResult?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'prioritizes folder then date, excludes self/deleted, deduplicates and caps at ten',
    (tester) async {
      await openDialog(
        tester,
        Future.value([
          recording('other', '其他文件夹', folder: 'other', day: 21),
          recording('old', '同文件夹旧标题', day: 1),
          recording('new', '同文件夹新标题', day: 20),
          recording('duplicate', '同文件夹新标题', day: 19),
          recording('current', '自身不应展示'),
          recording('same', '新录音'),
          recording('deleted', '已删除', deleted: true),
          recording('empty', '   '),
          for (var day = 2; day <= 10; day++)
            recording('r$day', '标题$day', day: day),
        ]),
      );
      final titles = tester
          .widgetList<TextButton>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextButton),
            ),
          )
          .map((b) => (b.child! as Text).data)
          .toList();
      expect(titles, [
        '同文件夹新标题',
        for (var day = 10; day >= 2; day--) '标题$day',
        '取消',
      ]);
      expect(find.text('使用最近录音的标题'), findsOneWidget);
    },
  );

  testWidgets(
    'fills title, keeps editing focus, then returns edited value only on save',
    (tester) async {
      String? result;
      final source = recording('old', '会议一');
      await openDialog(
        tester,
        Future.value([source]),
        onResult: (value) => result = value,
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '新录音');
      await tester.tap(find.widgetWithText(TextButton, '会议一'));
      await tester.pumpAndSettle();
      expect(field.controller!.text, '会议一');
      expect(
        field.controller!.selection,
        const TextSelection.collapsed(offset: 3),
      );
      expect(field.focusNode!.hasFocus, isTrue);
      expect(result, isNull);
      await tester.enterText(find.byType(TextField), '会议二');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(result, '会议二');
      expect(source.title, '会议一');
    },
  );

  testWidgets(
    'late suggestions preserve edits and cancellation discards a selected title',
    (tester) async {
      final recent = Completer<List<Recording>>();
      String? result = 'unchanged';
      await openDialog(
        tester,
        recent.future,
        onResult: (value) => result = value,
      );
      await tester.enterText(find.byType(TextField), '正在输入');
      recent.complete([recording('old', '历史标题', folder: 'other')]);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '正在输入',
      );
      await tester.tap(find.widgetWithText(TextButton, '历史标题'));
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );

  testWidgets('failed suggestions still allow manual rename', (tester) async {
    final recent = Completer<List<Recording>>();
    String? result;
    await openDialog(
      tester,
      recent.future,
      onResult: (value) => result = value,
    );
    recent.completeError(StateError('read failed'));
    await tester.pumpAndSettle();
    expect(find.text('使用最近录音的标题'), findsNothing);
    await tester.enterText(find.byType(TextField), '手动标题');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result, '手动标题');
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'scrolls with keyboard, long titles and large text: $locale $mode',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final longTitle = List.filled(10, '会议记录').join();
          await openDialog(
            tester,
            Future.value([
              for (var i = 0; i < 10; i++) recording('r$i', '$longTitle$i'),
            ]),
            locale: locale,
            themeMode: mode,
            textScale: 2,
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.widgetWithText(TextButton, '${longTitle}0'),
          );
          await tester.tap(find.widgetWithText(TextButton, '${longTitle}0'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            '${longTitle}0',
          );
          final save = locale.languageCode == 'zh' ? '保存' : 'Save';
          await tester.ensureVisible(find.widgetWithText(FilledButton, save));
          await tester.tap(find.widgetWithText(FilledButton, save));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
