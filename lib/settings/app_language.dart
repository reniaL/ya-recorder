import 'package:flutter/widgets.dart';

/// Stable storage values; add languages here together with their ARB resources.
enum AppLanguage {
  simplifiedChinese(
    'zh',
    '简体中文',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ),
  english('en', 'English', Locale('en'));

  const AppLanguage(this.code, this.nativeName, this.locale);
  final String code;
  final String nativeName;
  final Locale locale;

  static AppLanguage fromCode(Object? code) => values.firstWhere(
    (language) => language.code == code,
    orElse: () => simplifiedChinese,
  );
}
