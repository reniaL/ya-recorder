import 'package:ya_recorder/l10n/localization.dart';
import 'package:ya_recorder/theme/app_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/recording/recording_service.dart';
import 'package:ya_recorder/settings/recording_settings_page.dart';
import 'package:ya_recorder/settings/app_language.dart';
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

  InkWell choiceInkWell(WidgetTester tester, Finder row) =>
      tester.widget<InkWell>(
        find.descendant(of: row, matching: find.byType(InkWell)),
      );

  void expectEqualUnclippedRows(WidgetTester tester, List<Finder> rows) {
    final list = find.byKey(const Key('settingsChoiceList'));
    final listRect = tester.getRect(list);
    final height = tester.getSize(rows.first).height;
    for (final row in rows) {
      final rect = tester.getRect(row);
      expect(rect.height, height);
      expect(rect.top, greaterThanOrEqualTo(listRect.top + 6 - 0.01));
      expect(rect.bottom, lessThanOrEqualTo(listRect.bottom - 6 + 0.01));
    }
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.maxScrollExtent, 0);
  }

  for (final language in AppLanguage.values) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'UIR-08 grouped adaptive preferences $language $brightness $scale',
          (tester) async {
            final size = Size(scale == 1 ? 390 : 320, 720);
            var foldersOpened = 0;
            var deletedOpened = 0;
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await tester.pumpWidget(
              MaterialApp(
                locale: language.locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                theme: buildAppTheme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: RecordingSettingsPage(
                  store: store,
                  service: service,
                  onOpenFolders: () => foldersOpened++,
                  onOpenRecentlyDeleted: () => deletedOpened++,
                ),
              ),
            );
            await tester.pumpAndSettle();
            final format = find.byKey(const Key('defaultRecordingFormat'));
            final context = tester.element(format);
            final strings = l10n(context);
            expect(
              tester
                  .getTopLeft(find.byKey(const Key('recordingSettingsGroup')))
                  .dy,
              lessThan(tester.getTopLeft(format).dy),
            );
            expect(
              tester.getTopLeft(format).dy,
              lessThan(
                tester
                    .getTopLeft(
                      find.byKey(const Key('appearanceSettingsGroup')),
                    )
                    .dy,
              ),
            );
            final label = find.descendant(
              of: format,
              matching: find.text(strings.defaultFormat),
            );
            final value = find.descendant(
              of: format,
              matching: find.text('AAC'),
            );
            if (scale == 1) {
              expect(
                tester.getCenter(label).dx,
                lessThan(tester.getCenter(value).dx),
              );
              expect(
                tester.getCenter(label).dy,
                closeTo(tester.getCenter(value).dy, 0.1),
              );
            } else {
              expect(
                tester.getRect(label).bottom,
                lessThanOrEqualTo(tester.getRect(value).top),
              );
            }
            expect(find.byIcon(Icons.unfold_more_rounded), findsNothing);
            final themeRow = find.byKey(const Key('themeMode'));
            await tester.scrollUntilVisible(themeRow, 150);
            await tester.pumpAndSettle();
            await tester.tap(themeRow);
            await tester.pumpAndSettle();
            final selected = find.byKey(const Key('chooseTheme-system'));
            final material = tester.widget<Material>(
              find
                  .ancestor(of: selected, matching: find.byType(Material))
                  .first,
            );
            expect(material.elevation, AppMenuStyle.elevation);
            expect(
              material.borderRadius,
              BorderRadius.circular(AppMenuStyle.radius),
            );
            expect(
              material.color,
              Theme.of(
                tester.element(themeRow),
              ).colorScheme.surfaceContainerLow,
            );
            expect(tester.getSize(selected).height, greaterThanOrEqualTo(48));
            expect(tester.takeException(), isNull);
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            expect(store.writes, 0);
            final folders = find.byKey(const Key('manageFoldersSettings'));
            final deleted = find.byKey(const Key('recentlyDeletedSettings'));
            await tester.scrollUntilVisible(folders, 150);
            expect(find.text(strings.recordingManagementGroup), findsOneWidget);
            expect(find.text(strings.manageFolders), findsOneWidget);
            await tester.tap(folders);
            await tester.scrollUntilVisible(deleted, 150);
            expect(find.text(strings.recentlyDeleted), findsOneWidget);
            await tester.tap(deleted);
            expect(foldersOpened, 1);
            expect(deletedOpened, 1);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  test(
    'UIR-08 themes keep text and state colors readable on neutral surfaces',
    () {
      double contrast(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
      }

      for (final brightness in Brightness.values) {
        final theme = buildAppTheme(brightness);
        final colors = theme.colorScheme;
        expect(
          contrast(colors.onSurface, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(colors.onSurfaceVariant, colors.surfaceContainerLow),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(colors.error, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(
            colors.primary,
            Color.alphaBlend(
              AppMenuStyle.selectedColor(colors),
              colors.surfaceContainerLow,
            ),
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(theme.popupMenuTheme.shape, AppMenuStyle.shape);
      }
    },
  );

  testWidgets(
    'all preference menus have equal rows and show the full last row',
    (tester) async {
      await open(tester);
      for (final entry in {
        'appLanguage': ['chooseLanguage-zh', 'chooseLanguage-en'],
        'themeMode': [
          'chooseTheme-system',
          'chooseTheme-light',
          'chooseTheme-dark',
        ],
        'defaultRecordingFormat': ['chooseFormat-aac', 'chooseFormat-mp3'],
      }.entries) {
        await tester.tap(find.byKey(Key(entry.key)));
        await tester.pumpAndSettle();
        expectEqualUnclippedRows(tester, [
          for (final key in entry.value) find.byKey(Key(key)),
        ]);
        await tester.tapAt(const Offset(4, 400));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('settingsChoiceList')), findsNothing);
      }
      expect(store.writes, 0);
    },
  );

  testWidgets('theme selection persists; failed save keeps old selection', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('跟随系统'), findsOneWidget);
    await tester.tap(find.byKey(const Key('themeMode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chooseTheme-dark')));
    await tester.pumpAndSettle();
    expect(store.themeMode, ThemeMode.dark);
    expect(find.text('深色模式'), findsOneWidget);
    store.failWrite = true;
    await tester.tap(find.byKey(const Key('themeMode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chooseTheme-light')));
    await tester.pumpAndSettle();
    expect(store.themeMode, ThemeMode.dark);
    expect(find.text('无法保存主题，请重试。'), findsOneWidget);
    store.failWrite = false;
    await tester.tap(find.byKey(const Key('themeMode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chooseTheme-light')));
    await tester.pumpAndSettle();
    expect(store.themeMode, ThemeMode.light);
  });

  testWidgets(
    'language writes persist; native and storage failures retain the old language',
    (tester) async {
      await open(tester);
      Future<void> chooseEnglish() async {
        await tester.tap(find.byKey(const Key('appLanguage')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('chooseLanguage-en')));
        await tester.pumpAndSettle();
      }

      store.failWrite = true;
      await chooseEnglish();
      expect(store.language, AppLanguage.simplifiedChinese);
      expect(service.language, 'zh');
      expect(find.text('无法保存语言，请重试。'), findsOneWidget);
      store.failWrite = false;
      service.failLanguage = true;
      await chooseEnglish();
      expect(store.language, AppLanguage.simplifiedChinese);
      service.failLanguage = false;
      await chooseEnglish();
      expect(store.language, AppLanguage.english);
      expect(service.language, 'en');
      expect(find.text('English'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(find.text('English'), findsOneWidget);
    },
  );

  testWidgets(
    'language read failure retries and pending save blocks repeat choices and back',
    (tester) async {
      store.failLanguageRead = true;
      await open(tester);
      expect(find.text('无法读取语言设置，请重试。'), findsOneWidget);
      store.failLanguageRead = false;
      await tester.tap(find.text('重试读取语言'));
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      store.writeGate = gate.future;
      await tester.tap(find.byKey(const Key('appLanguage')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chooseLanguage-en')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final row = tester.widget<ListTile>(find.byKey(const Key('appLanguage')));
      expect(row.onTap, isNull);
      expect(
        tester.widget<PopScope>(find.byType(PopScope).first).canPop,
        isFalse,
      );
      expect(store.language, AppLanguage.simplifiedChinese);
      gate.complete();
      await tester.pumpAndSettle();
      expect(store.language, AppLanguage.english);
    },
  );

  testWidgets(
    'choosing MP3 persists immediately; reopening reads the preference',
    (tester) async {
      await open(tester);
      expect(find.text('AAC'), findsOneWidget);
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
    'native AAC capability enables AAC and hides old M4A for new selection',
    (tester) async {
      store.format = RecordingFormat.m4a;
      service.available = [RecordingFormat.aac, RecordingFormat.mp3];
      await open(tester);
      await choose(tester);
      expect(find.byKey(const Key('chooseFormat-m4a')), findsNothing);

      expect(
        choiceInkWell(tester, find.byKey(const Key('chooseFormat-aac'))).onTap,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('chooseFormat-aac')));
      await tester.pumpAndSettle();
      expect(store.format, RecordingFormat.aac);
      expect(store.writes, 1);
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      expect(find.text('AAC'), findsOneWidget);
    },
  );

  testWidgets(
    'native gate disables MP3 while preserving an existing MP3 preference',
    (tester) async {
      service.available = [RecordingFormat.aac];
      store.format = RecordingFormat.mp3;
      await open(tester);
      expect(find.text('MP3'), findsOneWidget);
      await choose(tester);
      final mp3 = find.byKey(const Key('chooseFormat-mp3'));
      expect(choiceInkWell(tester, mp3).onTap, isNull);
      expect(find.text('MP3 暂不可用'), findsOneWidget);
      await tester.tap(mp3);
      await tester.pumpAndSettle();
      expect(store.writes, 0);
      await tester.tap(find.byKey(const Key('chooseFormat-aac')));
      await tester.pumpAndSettle();
      expect(store.format, RecordingFormat.aac);
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
    expect(store.format, RecordingFormat.aac);
    await choose(tester);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byKey(const Key('chooseFormat-aac'))),
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
        isSelected: true,
        label: 'AAC\nADTS 文件，后缀 .aac',
      ),
    );
    semantics.dispose();
    store.failWrite = false;
    await tester.tap(find.byKey(const Key('chooseFormat-mp3')));
    await tester.pumpAndSettle();
    expect(store.format, RecordingFormat.mp3);
    expect(store.writes, 2);
  });

  testWidgets('pending save blocks duplicate writes and page navigation', (
    tester,
  ) async {
    final gate = Completer<void>();
    store.writeGate = gate.future;
    await open(tester);
    await choose(tester);
    await tester.tap(find.byKey(const Key('chooseFormat-mp3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('settingsChoiceList')), findsNothing);
    final row = tester.widget<ListTile>(
      find.byKey(const Key('defaultRecordingFormat')),
    );
    expect(row.onTap, isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(store.writes, 1);
    expect(store.format, RecordingFormat.aac);
    expect(
      tester.widget<PopScope>(find.byType(PopScope).first).canPop,
      isFalse,
    );
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
    await tester.tapAt(const Offset(4, 400));
    await tester.pumpAndSettle();
    await choose(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await choose(tester);
    await tester.tap(find.byKey(const Key('chooseFormat-aac')));
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
      choiceInkWell(tester, find.byKey(const Key('chooseFormat-mp3'))).onTap,
      isNotNull,
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
          'AAC',
        );
        await choose(tester);
        expectEqualUnclippedRows(tester, [
          find.byKey(const Key('chooseFormat-aac')),
          find.byKey(const Key('chooseFormat-mp3')),
        ]);
        for (final format in [RecordingFormat.aac, RecordingFormat.mp3]) {
          final row = find.byKey(Key('chooseFormat-${format.wireName}'));
          expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
          expect(tester.getSemantics(row).label, contains(format.label));
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('chooseFormat-mp3')));
        await tester.pumpAndSettle();
        expect(find.text('MP3'), findsOneWidget);
        await tester.tap(find.byKey(const Key('themeMode')));
        await tester.pumpAndSettle();
        for (final mode in ThemeMode.values) {
          final row = find.byKey(Key('chooseTheme-${mode.name}'));
          expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
        }
        await tester.tap(find.byKey(const Key('chooseTheme-dark')));
        await tester.pumpAndSettle();
        expect(store.themeMode, ThemeMode.dark);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}

class _Store extends RecordingStore {
  _Store() : super(databasePath: 'unused', databaseFactory: databaseFactoryFfi);
  ThemeMode themeMode = ThemeMode.system;
  AppLanguage language = AppLanguage.simplifiedChinese;
  bool failLanguageRead = false;
  @override
  Future<AppLanguage> getAppLanguage() async {
    if (failLanguageRead) throw StateError('read failed');
    return language;
  }

  @override
  Future<void> setAppLanguage(AppLanguage value) async {
    if (writeGate != null) await writeGate;
    if (failWrite) throw StateError('write failed');
    language = value;
  }

  @override
  Future<ThemeMode> getThemeMode() async => themeMode;
  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    if (failWrite) throw StateError('write failed');
    themeMode = mode;
  }

  RecordingFormat format = RecordingFormat.aac;
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
  String language = 'zh';
  bool failLanguage = false;
  @override
  Future<void> setAppLanguage(String code) async {
    if (failLanguage) throw StateError('native synchronization failed');
    language = code;
  }

  List<RecordingFormat> available = [RecordingFormat.aac, RecordingFormat.mp3];
  bool failRead = false;
  @override
  Future<List<RecordingFormat>> getAvailableFormats() async {
    if (failRead) throw StateError('capability unavailable');
    return available;
  }
}
