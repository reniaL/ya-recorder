import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ya_recorder/l10n/app_localizations_en.dart';
import 'package:ya_recorder/l10n/localization.dart';
import 'package:ya_recorder/settings/app_language.dart';
import 'package:ya_recorder/settings/recording_settings_page.dart';
import 'package:ya_recorder/recording/recording_format.dart';
import 'package:ya_recorder/recording/recording_service.dart';
import 'package:ya_recorder/storage/recording_store.dart';

void main() {
  test(
    'Chinese and English resources cover the same messages and placeholders',
    () {
      final en =
          jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
              as Map<String, dynamic>;
      final zh =
          jsonDecode(File('lib/l10n/app_zh.arb').readAsStringSync())
              as Map<String, dynamic>;
      final keys = en.keys.where((key) => !key.startsWith('@')).toSet();
      expect(zh.keys.where((key) => !key.startsWith('@')).toSet(), keys);
      for (final key in keys) {
        expect(en[key], isNotEmpty, reason: key);
        expect(zh[key], isNotEmpty, reason: key);
        expect(
          RegExp(r'[\u3400-\u9fff]').hasMatch(en[key] as String),
          isFalse,
          reason: key,
        );
        expect(zh['@$key'], en['@$key'], reason: 'Placeholder types for $key');
      }
    },
  );

  test('English quantities use natural singular and plural wording', () {
    final strings = AppLocalizationsEn();
    expect(strings.recordingCount(0), '0 recordings');
    expect(strings.recordingCount(1), '1 recording');
    expect(strings.recordingCount(2), '2 recordings');
    expect(strings.backupRecordingsCount(1), '1 recording');
    expect(strings.backupRecordingsCount(2), '2 recordings');
    expect(strings.backupFoldersCount(1), '1 folder');
    expect(strings.backupFoldersCount(2), '2 folders');
    expect(strings.backupAddedResult(0), '0 recordings added');
    expect(strings.moveSelectedTitle(1), 'Move 1 recording to');
    expect(strings.moveSelectedTitle(2), 'Move 2 recordings to');
    expect(
      strings.deleteSelectedTitle(1),
      'Move 1 recording to Recently Deleted?',
    );
    expect(
      strings.deletionInfo('2026-10-08', 1),
      'Deleted on 2026-10-08\n1 day remaining',
    );
    expect(
      strings.deletionInfo('2026-10-08', 0),
      'Deleted on 2026-10-08\n0 days remaining',
    );
    expect(
      AppLanguage.fromCode('future-language'),
      AppLanguage.simplifiedChinese,
    );
  });

  for (final language in AppLanguage.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${language.code} settings and selectors fit 320px at 2x text in $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              locale: language.locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              theme: ThemeData(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: RecordingSettingsPage(
                store: _Store(language),
                service: _Service(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final context = tester.element(find.byKey(const Key('appLanguage')));
          expect(find.text(l10n(context).language), findsOneWidget);
          expect(
            tester.getSemantics(find.byKey(const Key('appLanguage'))).value,
            language.nativeName,
          );
          await tester.tap(find.byKey(const Key('appLanguage')));
          await tester.pumpAndSettle();
          for (final option in AppLanguage.values) {
            final row = find.byKey(Key('chooseLanguage-${option.code}'));
            expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
            expect(tester.getSemantics(row).label, option.nativeName);
          }
          await tester.tap(find.byKey(Key('chooseLanguage-${language.code}')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const Key('defaultRecordingFormat')),
          );
          await tester.tap(find.byKey(const Key('defaultRecordingFormat')));
          await tester.pumpAndSettle();
          expect(find.text('MP3'), findsOneWidget);
          expect(find.text('AAC'), findsOneWidget);
          expect(find.text(l10n(context).aacFormatDescription), findsOneWidget);
          expect(find.byKey(const Key('chooseFormat-m4a')), findsNothing);
          for (final format in [RecordingFormat.aac, RecordingFormat.mp3]) {
            final row = find.byKey(Key('chooseFormat-${format.wireName}'));
            expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
            expect(tester.getSemantics(row).label, contains(format.label));
          }
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
}

class _Store extends RecordingStore {
  _Store(this.language)
    : super(databasePath: 'unused', databaseFactory: databaseFactoryFfi);
  final AppLanguage language;
  @override
  Future<AppLanguage> getAppLanguage() async => language;
  @override
  Future<ThemeMode> getThemeMode() async => ThemeMode.system;
  @override
  Future<RecordingFormat> getDefaultRecordingFormat() async =>
      RecordingFormat.m4a;
}

class _Service extends RecordingService {
  @override
  Future<void> setAppLanguage(String code) async {}
  @override
  Future<List<RecordingFormat>> getAvailableFormats() async =>
      RecordingFormat.values;
}
