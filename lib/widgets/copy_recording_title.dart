import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/localization.dart';

Future<void> copyRecordingTitle(BuildContext context, String title) async {
  var copied = false;
  try {
    await Clipboard.setData(ClipboardData(text: title));
    copied = true;
  } catch (_) {
    // Report platform clipboard failures without changing the recording.
  }
  if (!context.mounted) return;
  final strings = l10n(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(copied ? strings.titleCopied : strings.copyTitleFailed),
      ),
    );
}
