import 'dart:math' as math;

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
  final _languageAnchorKey = GlobalKey();
  final _themeAnchorKey = GlobalKey();
  final _formatAnchorKey = GlobalKey();
  RecordingFormat? _format;
  List<RecordingFormat> _available = [];
  bool _loading = true;
  String? _error;
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

  Future<void> _chooseLanguage() async {
    if (_savingLanguage || _savingTheme || _language == null) return;
    final selected = await _showChoiceMenu<AppLanguage>(
      anchorKey: _languageAnchorKey,
      selected: _language!,
      choices: [
        for (final language in AppLanguage.values)
          _PopupChoice(
            language,
            language.nativeName,
            key: Key('chooseLanguage-${language.code}'),
          ),
      ],
    );
    if (selected != null && mounted) await _selectLanguage(selected);
  }

  Future<void> _selectLanguage(AppLanguage selected) async {
    if (_savingLanguage || _savingTheme || selected == _language) return;
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
    if (_savingTheme || _savingLanguage || _themeMode == null) return;
    final selected = await _showChoiceMenu<ThemeMode>(
      anchorKey: _themeAnchorKey,
      selected: _themeMode!,
      choices: [
        for (final mode in ThemeMode.values)
          _PopupChoice(
            mode,
            _themeLabel(mode),
            key: Key('chooseTheme-${mode.name}'),
          ),
      ],
    );
    if (selected != null && mounted) await _selectTheme(selected);
  }

  Future<void> _selectTheme(ThemeMode selected) async {
    if (_savingTheme || _savingLanguage || selected == _themeMode) return;
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
    if (_format == null || _savingFormat) return;
    setState(() => _formatError = null);
    final selected = await _showChoiceMenu<RecordingFormat>(
      anchorKey: _formatAnchorKey,
      selected: _format!,
      choices: [
        for (final format in [RecordingFormat.aac, RecordingFormat.mp3])
          _PopupChoice(
            format,
            format.label,
            key: Key('chooseFormat-${format.wireName}'),
            subtitle: _available.contains(format)
                ? format == RecordingFormat.aac
                      ? l10n(context).aacFormatDescription
                      : null
                : l10n(context).formatUnavailable(format.label),
            enabled: _available.contains(format),
          ),
      ],
    );
    if (selected != null && mounted) await _selectFormat(selected);
  }

  Future<void> _selectFormat(RecordingFormat format) async {
    if (_savingFormat || !_available.contains(format)) return;
    if (format == _format) return;
    setState(() {
      _savingFormat = true;
      _formatError = null;
    });
    try {
      await widget.store.setDefaultRecordingFormat(format);
      if (!mounted) return;
      setState(() {
        _format = format;
      });
    } catch (_) {
      if (mounted) setState(() => _formatError = 'formatSaveFailed');
    } finally {
      if (mounted) setState(() => _savingFormat = false);
    }
  }

  Future<T?> _showChoiceMenu<T>({
    required GlobalKey anchorKey,
    required T selected,
    required List<_PopupChoice<T>> choices,
  }) async {
    final anchorContext = anchorKey.currentContext;
    final anchorObject = anchorContext?.findRenderObject();
    final overlayObject = Navigator.of(
      context,
    ).overlay?.context.findRenderObject();
    if (anchorObject is! RenderBox ||
        overlayObject is! RenderBox ||
        !anchorObject.hasSize ||
        !overlayObject.hasSize) {
      return null;
    }
    final anchorTopLeft = anchorObject.localToGlobal(
      Offset.zero,
      ancestor: overlayObject,
    );
    final anchorRect = anchorTopLeft & anchorObject.size;
    final selectedIndex = choices.indexWhere(
      (choice) => choice.value == selected,
    );
    final barrierLabel = MaterialLocalizations.of(
      context,
    ).modalBarrierDismissLabel;

    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, _) => LayoutBuilder(
        builder: (context, constraints) {
          final media = MediaQuery.of(context);
          final safeTop = media.padding.top + 12;
          final safeBottom = constraints.maxHeight - media.padding.bottom - 12;
          final width = math.min(340.0, constraints.maxWidth - 32);
          const verticalPadding = 6.0;
          // Reserve the checkmark column in every row and use the tallest
          // choice for all rows, including wrapped descriptions and large text.
          final textWidth = width - 44 - 36;
          final theme = Theme.of(context);
          double textHeight(String text, TextStyle style) {
            final painter = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: Directionality.of(context),
              textScaler: media.textScaler,
              locale: Localizations.maybeLocaleOf(context),
            )..layout(maxWidth: textWidth);
            final height = painter.height;
            painter.dispose();
            return height;
          }

          final rowHeight = choices.fold<double>(60, (height, choice) {
            final titleHeight = textHeight(
              choice.label,
              theme.textTheme.titleMedium!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            );
            final subtitleHeight = choice.subtitle == null
                ? 0.0
                : 2 + textHeight(choice.subtitle!, theme.textTheme.bodySmall!);
            return math.max(
              height,
              math.max(
                choice.subtitle == null ? 60.0 : 76.0,
                titleHeight + subtitleHeight + 20,
              ),
            );
          }).ceilToDouble();
          final menuHeight = math.min(
            rowHeight * choices.length + verticalPadding * 2,
            safeBottom - safeTop,
          );
          final desiredTop =
              anchorRect.center.dy -
              verticalPadding -
              math.max(0, selectedIndex) * rowHeight -
              rowHeight / 2;
          final top = desiredTop
              .clamp(safeTop, safeBottom - menuHeight)
              .toDouble();
          final left = (anchorRect.right - width)
              .clamp(16.0, constraints.maxWidth - width - 16)
              .toDouble();

          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: width,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 12,
                  shadowColor: Colors.black.withValues(alpha: 0.24),
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(22),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: menuHeight),
                    child: ListView(
                      key: const Key('settingsChoiceList'),
                      padding: const EdgeInsets.symmetric(
                        vertical: verticalPadding,
                      ),
                      shrinkWrap: true,
                      children: [
                        for (final choice in choices)
                          _PopupChoiceTile<T>(
                            key: choice.key,
                            choice: choice,
                            height: rowHeight,
                            selected: choice.value == selected,
                            onTap: choice.enabled
                                ? () => Navigator.of(
                                    dialogContext,
                                  ).pop(choice.value)
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              alignment: Alignment.center,
              child: child,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_savingTheme && !_savingLanguage && !_savingFormat,
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
                      key: _languageAnchorKey,
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
                            : Icon(Icons.unfold_more_rounded),
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
                      key: _themeAnchorKey,
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
                            : Icon(Icons.unfold_more_rounded),
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
                        key: _formatAnchorKey,
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
                              : Icon(Icons.unfold_more_rounded),
                          onTap: _savingFormat ? null : _chooseFormat,
                        ),
                      ),
                      if (_formatError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(localizedMessage(context, _formatError!)),
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

class _PopupChoice<T> {
  const _PopupChoice(
    this.value,
    this.label, {
    required this.key,
    this.subtitle,
    this.enabled = true,
  });

  final T value;
  final Key key;
  final String label;
  final String? subtitle;
  final bool enabled;
}

class _PopupChoiceTile<T> extends StatelessWidget {
  const _PopupChoiceTile({
    super.key,
    required this.choice,
    required this.height,
    required this.selected,
    required this.onTap,
  });

  final _PopupChoice<T> choice;
  final double height;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      checked: selected,
      enabled: choice.enabled,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          color: selected
              ? colors.primaryContainer.withValues(alpha: 0.72)
              : null,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      choice.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: choice.enabled
                            ? (selected ? colors.primary : colors.onSurface)
                            : colors.onSurface.withValues(alpha: 0.38),
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                    if (choice.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        choice.subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 24,
                child: selected
                    ? Icon(Icons.check_rounded, color: colors.primary)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
