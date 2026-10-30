import 'package:flutter/material.dart';

import '../../app/theme/tokens.g.dart';

/// Botão de ação principal com estado de carregamento.
///
/// Enquanto [isLoading] for verdadeiro o botão fica desabilitado, evitando envios duplicados.
class EvoButton extends StatelessWidget {
  const EvoButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = EvoButtonVariant.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final EvoButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final foreground = variant == EvoButtonVariant.primary
        ? EvoColors.onAccent
        : EvoColors.textPrimary;

    final Widget content = isLoading
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: foreground,
              semanticsLabel: 'Carregando',
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: EvoSpace.sm),
              ],
              Text(label),
            ],
          );

    return switch (variant) {
      EvoButtonVariant.primary => FilledButton(
        onPressed: enabled ? onPressed : null,
        child: content,
      ),
      EvoButtonVariant.secondary => OutlinedButton(
        onPressed: enabled ? onPressed : null,
        child: content,
      ),
    };
  }
}

enum EvoButtonVariant { primary, secondary }
