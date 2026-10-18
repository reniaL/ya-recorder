import '../l10n/localization.dart';
import 'package:flutter/material.dart';
import '../backup/backup_controller.dart';

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
    this.backupController,
    this.onOpenBackup,
  });

  final RecordingStore store;
  final RecordingService service;
  final ValueChanged<ThemeMode>? onThemeChanged;
  final ValueChanged<AppLanguage>? onLanguageChanged;
  final BackupController? backupController;
  final VoidCallback? onOpenBackup;

  @override
  State<RecordingSettingsPage> createState() => _RecordingSettingsPageState();
}

class _RecordingSettingsPageState extends State<RecordingSettingsPage> {
  RecordingFormat? _format;
  List<RecordingFormat> _available = [];
  bool _loading = true;
  String? _error;
  bool _languageExpanded = false;
  bool _themeExpanded = false;
  bool _formatExpanded = false;
  bool _savingFormat = false;
  String? _formatError;

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

  void _toggleLanguage() {
    if (_savingLanguage || _savingTheme || _language == null) return;
    setState(() {
      _languageExpanded = !_languageExpanded;
      _themeExpanded = false;
      _formatExpanded = false;
    });
  }

  Future<void> _selectLanguage(AppLanguage selected) async {
    if (_savingLanguage || _savingTheme || selected == _language) {
      setState(() => _languageExpanded = false);
      return;
    }
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
      setState(() => _languageExpanded = false);
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

  void _toggleTheme() {
    if (_savingTheme || _savingLanguage || _themeMode == null) return;
    setState(() {
      _themeExpanded = !_themeExpanded;
      _languageExpanded = false;
      _formatExpanded = false;
    });
  }

  Future<void> _selectTheme(ThemeMode selected) async {
    if (_savingTheme || _savingLanguage || selected == _themeMode) {
      setState(() => _themeExpanded = false);
      return;
    }
    setState(() {
      _savingTheme = true;
      _themeError = null;
    });
    try {
      await widget.store.setThemeMode(selected);
      if (!mounted) return;
      setState(() => _themeMode = selected);
      widget.onThemeChanged?.call(selected);
      setState(() => _themeExpanded = false);
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

  void _toggleFormat() {
    if (_format == null || _savingFormat) return;
    setState(() {
      _formatExpanded = !_formatExpanded;
      _languageExpanded = false;
      _themeExpanded = false;
      _formatError = null;
    });
  }

  Future<void> _selectFormat(RecordingFormat format) async {
    if (_savingFormat || !_available.contains(format)) return;
    if (format == _format) {
      setState(() => _formatExpanded = false);
      return;
    }
    setState(() {
      _savingFormat = true;
      _formatError = null;
    });
    try {
      await widget.store.setDefaultRecordingFormat(format);
      if (!mounted) return;
      setState(() {
        _format = format;
        _formatExpanded = false;
      });
    } catch (_) {
      if (mounted) setState(() => _formatError = 'formatSaveFailed');
    } finally {
      if (mounted) setState(() => _savingFormat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          !_savingTheme &&
          !_savingLanguage &&
          !_savingFormat &&
          !_languageExpanded &&
          !_themeExpanded &&
          !_formatExpanded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop &&
            !_savingTheme &&
            !_savingLanguage &&
            !_savingFormat &&
            (_languageExpanded || _themeExpanded || _formatExpanded)) {
          setState(() {
            _languageExpanded = false;
            _themeExpanded = false;
            _formatExpanded = false;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n(context).settings)),
        body: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  children: [
                    if (widget.backupController != null)
                      AnimatedBuilder(
                        animation: widget.backupController!,
                        builder: (context, _) => ListTile(
                          key: const Key('backupSettings'),
                          title: Text(l10n(context).backupTitle),
                          subtitle: Text(
                            widget.backupController!.busy
                                ? l10n(context).backupCurrentTask
                                : widget.backupController!.outcome == null
                                ? l10n(context).backupDescription
                                : l10n(context).backupLastResult,
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: widget.onOpenBackup,
                        ),
                      ),
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
                            : Icon(
                                _languageExpanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                              ),
                        onTap:
                            _language == null || _savingLanguage || _savingTheme
                            ? null
                            : _toggleLanguage,
                      ),
                    ),
                    _InlineChoiceCard(
                      expanded: _languageExpanded,
                      children: [
                        for (final language in AppLanguage.values)
                          Semantics(
                            checked: language == _language,
                            inMutuallyExclusiveGroup: true,
                            child: ListTile(
                              key: Key('chooseLanguage-${language.code}'),
                              title: Text(language.nativeName),
                              selected: language == _language,
                              trailing: language == _language
                                  ? Icon(
                                      Icons.check_circle_rounded,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    )
                                  : null,
                              onTap: _savingLanguage
                                  ? null
                                  : () => _selectLanguage(language),
                            ),
                          ),
                      ],
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
                            : Icon(
                                _themeExpanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                              ),
                        onTap:
                            _themeMode == null ||
                                _savingTheme ||
                                _savingLanguage
                            ? null
                            : _toggleTheme,
                      ),
                    ),
                    _InlineChoiceCard(
                      expanded: _themeExpanded,
                      children: [
                        for (final mode in ThemeMode.values)
                          Semantics(
                            checked: mode == _themeMode,
                            inMutuallyExclusiveGroup: true,
                            child: ListTile(
                              key: Key('chooseTheme-${mode.name}'),
                              title: Text(_themeLabel(mode)),
                              selected: mode == _themeMode,
                              trailing: mode == _themeMode
                                  ? Icon(
                                      Icons.check_circle_rounded,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    )
                                  : null,
                              onTap: _savingTheme
                                  ? null
                                  : () => _selectTheme(mode),
                            ),
                          ),
                      ],
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
                          trailing: _savingFormat
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(),
                                )
                              : Icon(
                                  _formatExpanded
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                ),
                          onTap: _toggleFormat,
                        ),
                      ),
                      _InlineChoiceCard(
                        expanded: _formatExpanded,
                        children: [
                          for (final format in [
                            RecordingFormat.aac,
                            RecordingFormat.mp3,
                          ])
                            Semantics(
                              checked: _format == format,
                              inMutuallyExclusiveGroup: true,
                              child: ListTile(
                                key: Key('chooseFormat-${format.wireName}'),
                                leading: Icon(
                                  _format == format
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: _format == format
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                                title: Text(format.label),
                                subtitle: _available.contains(format)
                                    ? format == RecordingFormat.aac
                                          ? Text(
                                              l10n(
                                                context,
                                              ).aacFormatDescription,
                                            )
                                          : null
                                    : Text(
                                        l10n(
                                          context,
                                        ).formatUnavailable(format.label),
                                      ),
                                enabled:
                                    !_savingFormat &&
                                    _available.contains(format),
                                onTap: () => _selectFormat(format),
                              ),
                            ),
                          if (_formatError != null)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                localizedMessage(context, _formatError!),
                              ),
                            ),
                          if (_savingFormat)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(l10n(context).saving),
                                ],
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _savingFormat
                                  ? null
                                  : () =>
                                        setState(() => _formatExpanded = false),
                              child: Text(l10n(context).cancel),
                            ),
                          ),
                        ],
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

class _InlineChoiceCard extends StatelessWidget {
  const _InlineChoiceCard({required this.expanded, required this.children});

  final bool expanded;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: expanded
          ? Card(
              key: const Key('inlineChoiceCard'),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              clipBehavior: Clip.antiAlias,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
