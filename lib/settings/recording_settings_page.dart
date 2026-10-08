import 'package:flutter/material.dart';

import '../recording/recording_format.dart';
import '../recording/recording_service.dart';
import '../storage/recording_store.dart';

class RecordingSettingsPage extends StatefulWidget {
  const RecordingSettingsPage({
    super.key,
    required this.store,
    required this.service,
  });

  final RecordingStore store;
  final RecordingService service;

  @override
  State<RecordingSettingsPage> createState() => _RecordingSettingsPageState();
}

class _RecordingSettingsPageState extends State<RecordingSettingsPage> {
  RecordingFormat? _format;
  List<RecordingFormat> _available = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

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
        setState(() => _error = '无法读取录音格式设置，请重试。');
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
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  if (_error != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(_error!, semanticsLabel: _error),
                    ),
                    TextButton(onPressed: _load, child: const Text('重试')),
                  ] else ...[
                    Semantics(
                      value: _format!.label,
                      child: ListTile(
                        key: const Key('defaultRecordingFormat'),
                        title: const Text('默认录音格式'),
                        subtitle: Text(_format!.label),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _chooseFormat,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('用于下一次录音，已有录音保持原格式'),
                    ),
                  ],
                ],
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
          _error = '无法保存录音格式，请重试。';
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
              const ListTile(title: Text('默认录音格式')),
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
                        : Text('${format.label} 暂不可用'),
                    enabled: !_saving && widget.available.contains(format),
                    onTap: () => _select(format),
                  ),
                ),
              if (_saving) ...[
                const CircularProgressIndicator(),
                const Text('正在保存'),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, semanticsLabel: _error),
                ),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
