import 'package:flutter/material.dart';

import '../l10n/localization.dart';

/// Shared risk styling; the label must describe the actual consequence.
class DestructiveActionButton extends StatelessWidget {
  const DestructiveActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.error,
          foregroundColor: colors.onError,
          minimumSize: const Size(48, 48),
        ),
        child: Text(label, textAlign: TextAlign.center),
      );
    }
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: colors.error,
        minimumSize: const Size(48, 48),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

class DestructiveConfirmationDialog extends StatelessWidget {
  const DestructiveConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onConfirm,
    this.alternativeAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onConfirm;
  final Widget? alternativeAction;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: Text(l10n(context).cancel),
        ),
        ?alternativeAction,
        DestructiveActionButton(label: actionLabel, onPressed: onConfirm),
      ],
    );
  }
}
