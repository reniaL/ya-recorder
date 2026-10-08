import '../l10n/localization.dart';
import 'package:flutter/material.dart';

import '../recording/recording_format.dart';
import '../recording/recording_service.dart';
import '../storage/recording_store.dart';
import 'app_language.dart';

class RecordingSettingsPage extends StatefulWidget {
  const RecordingSettingsPage({
    super.key,
    required this.store,
    required this.service,
    this.onThemeChanged,
    this.onLanguageChanged,
  });

  final RecordingStore store;
  final RecordingService service;
  final ValueChanged<ThemeMode>? onThemeChanged;
  final ValueChanged<AppLanguage>? onLanguageChanged;

  @override
  State<RecordingSettingsPage> createState() => _RecordingSettingsPageState();
}

class _RecordingSettingsPageState extends State<RecordingSettingsPage> {
  RecordingFormat? _format;
  List<RecordingFormat> _available = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _loadTheme();
    _loadLanguage();
  }

  AppLanguage? _language;
  bool _savingLanguage = false;
  String? _languageError;

  Future<void> _loadLanguage() async {
    try {
      final language = await widget.store.getAppLanguage();
      await widget.service.setAppLanguage(language.code);
      if (!mounted) return;
      setState(() {
        _language = language;
        _languageError = null;
      });
      widget.onLanguageChanged?.call(language);
    } catch (_) {
      if (mounted) setState(() => _languageError = 'languageReadFailed');
    }
  }

  Future<void> _chooseLanguage() async {
    final selected = await showModalBottomSheet<AppLanguage>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n(context).language),
              ),
              for (final language in AppLanguage.values)
                Semantics(
                  checked: language == _language,
                  inMutuallyExclusiveGroup: true,
                  child: ListTile(
                    key: Key('chooseLanguage-${language.code}'),
                    title: Text(language.nativeName),
                    selected: language == _language,
                    trailing: language == _language
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(context, language),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null || selected == _language) return;
    final previous = _language!;
    setState(() {
      _savingLanguage = true;
      _languageError = null;
    });
    try {
      // Native notifications and Flutter UI must agree. Roll back native
      // preferences if the authoritative SQLite write fails.
      await widget.service.setAppLanguage(selected.code);
      await widget.store.setAppLanguage(selected);
      if (!mounted) return;
      setState(() => _language = selected);
      widget.onLanguageChanged?.call(selected);
    } catch (_) {
      try {
        await widget.service.setAppLanguage(previous.code);
      } catch (_) {
        // Startup will resynchronize from SQLite on the next launch.
      }
      if (mounted) setState(() => _languageError = 'languageSaveFailed');
    } finally {
      if (mounted) setState(() => _savingLanguage = false);
    }
  }

  ThemeMode? _themeMode;
  bool _savingTheme = false;
  String? _themeError;

  Future<void> _loadTheme() async {
    try {
      final mode = await widget.store.getThemeMode();
      if (!mounted) return;
      setState(() {
        _themeMode = mode;
        _themeError = null;
      });
      widget.onThemeChanged?.call(mode);
    } catch (_) {
      if (mounted) setState(() => _themeError = 'themeReadFailed');
    }
  }

  Future<void> _chooseTheme() async {
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(l10n(context).theme),
              ),
              for (final mode in ThemeMode.values)
                ListTile(
                  key: Key('chooseTheme-${mode.name}'),
                  title: Text(_themeLabel(mode)),
                  selected: mode == _themeMode,
                  trailing: mode == _themeMode ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, mode),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null || selected == _themeMode) return;
    setState(() {
      _savingTheme = true;
      _themeError = null;
    });
    try {
      await widget.store.setThemeMode(selected);
      if (!mounted) return;
      setState(() => _themeMode = selected);
      widget.onThemeChanged?.call(selected);
    } catch (_) {
      if (mounted) setState(() => _themeError = 'themeSaveFailed');
    } finally {
      if (mounted) setState(() => _savingTheme = false);
    }
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => l10n(context).systemTheme,
    ThemeMode.light => l10n(context).lightTheme,
    ThemeMode.dark => l10n(context).darkTheme,
  };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final format = await widget.store.getDefaultRecordingFormat();
      final available = await widget.service.getAvailableFormats();
      if (!mounted) return;
      setState(() {
        _format = format;
        _available = available;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'formatReadFailed');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseFormat() async {
    final selected = await showModalBottomSheet<RecordingFormat>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _FormatChooser(
        current: _format!,
        available: _available,
        store: widget.store,
      ),
    );
    if (mounted && selected != null) setState(() => _format = selected);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_savingTheme && !_savingLanguage,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n(context).settings)),
        body: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  children: [
                    Semantics(
                      value: _language?.nativeName,
                      child: ListTile(
                        key: const Key('appLanguage'),
                        title: Text(l10n(context).language),
                        subtitle: Text(
                          _language?.nativeName ?? l10n(context).reading,
                        ),
                        trailing: _savingLanguage
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(),
                              )
                            : const Icon(Icons.chevron_right_rounded),
                        onTap:
                            _language == null || _savingLanguage || _savingTheme
                            ? null
                            : _chooseLanguage,
                      ),
                    ),
                    if (_languageError != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(localizedMessage(context, _languageError!)),
                      ),
                      if (_language == null)
                        TextButton(
                          onPressed: _loadLanguage,
                          child: Text(l10n(context).retryLanguage),
                        ),
                    ],
                    Semantics(
                      value: _themeMode == null
                          ? null
                          : _themeLabel(_themeMode!),
                      child: ListTile(
                        key: const Key('themeMode'),
                        title: Text(l10n(context).theme),
                        subtitle: Text(
                          _themeMode == null
                              ? l10n(context).reading
                              : _themeLabel(_themeMode!),
                        ),
                        trailing: _savingTheme
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(),
                              )
                            : const Icon(Icons.chevron_right_rounded),
                        onTap:
                            _themeMode == null ||
                                _savingTheme ||
                                _savingLanguage
                            ? null
                            : _chooseTheme,
                      ),
                    ),
                    if (_themeError != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(localizedMessage(context, _themeError!)),
                      ),
                      if (_themeMode == null)
                        TextButton(
                          onPressed: _loadTheme,
                          child: Text(l10n(context).retryTheme),
                        ),
                    ],
                    if (_error != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(localizedMessage(context, _error!)),
                      ),
                      TextButton(
                        onPressed: _load,
                        child: Text(l10n(context).retry),
                      ),
                    ] else ...[
                      Semantics(
                        value: _format!.label,
                        child: ListTile(
                          key: const Key('defaultRecordingFormat'),
                          title: Text(l10n(context).defaultFormat),
                          subtitle: Text(_format!.label),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _chooseFormat,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(l10n(context).formatDescription),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _FormatChooser extends StatefulWidget {
  const _FormatChooser({
    required this.current,
    required this.available,
    required this.store,
  });

  final RecordingFormat current;
  final List<RecordingFormat> available;
  final RecordingStore store;

  @override
  State<_FormatChooser> createState() => _FormatChooserState();
}

class _FormatChooserState extends State<_FormatChooser> {
  bool _saving = false;
  String? _error;

  Future<void> _select(RecordingFormat format) async {
    if (_saving || !widget.available.contains(format)) return;
    if (format == widget.current) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.setDefaultRecordingFormat(format);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'formatSaveFailed';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, format);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(l10n(context).defaultFormat)),
              for (final format in RecordingFormat.values)
                Semantics(
                  checked: widget.current == format,
                  inMutuallyExclusiveGroup: true,
                  child: ListTile(
                    key: Key('chooseFormat-${format.wireName}'),
                    leading: Icon(
                      widget.current == format
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(format.label),
                    subtitle: widget.available.contains(format)
                        ? null
                        : Text(l10n(context).formatUnavailable(format.label)),
                    enabled: !_saving && widget.available.contains(format),
                    onTap: () => _select(format),
                  ),
                ),
              if (_saving) ...[
                const CircularProgressIndicator(),
                Text(l10n(context).saving),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(localizedMessage(context, _error!)),
                ),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(l10n(context).cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
