import 'package:flutter/material.dart';

import '../../app/theme/motion.dart';
import '../../app/theme/tokens.g.dart';
import 'evo_focus_ring.dart';
import 'evo_pressable.dart';

/// Botão de ação em pílula, com estado de carregamento e resposta ao toque.
///
/// Enquanto [isLoading] for verdadeiro o botão fica desabilitado, evitando envios
/// duplicados. O conteúdo troca com um esmaecimento entre texto e indicador.
class EvoButton extends StatelessWidget {
  const EvoButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.variant = EvoButtonVariant.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Ícone depois do texto (ex.: seta de "continuar").
  final IconData? trailingIcon;
  final bool isLoading;
  final EvoButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final foreground = variant == EvoButtonVariant.primary
        ? EvoColors.onAccent
        : EvoColors.textPrimary;

    final Widget content = AnimatedSwitcher(
      duration: evoDuration(context, EvoMotion.fast),
      child: isLoading
          ? SizedBox.square(
              key: const ValueKey('loading'),
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: foreground,
                // Mantém o nome da ação: "Entrar, carregando".
                semanticsLabel: '$label, carregando',
              ),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: EvoSpace.sm),
                ],
                // Com fonte grande o rótulo quebra linha em vez de estourar.
                Flexible(child: Text(label, textAlign: TextAlign.center)),
                if (trailingIcon != null) ...[
                  const SizedBox(width: EvoSpace.sm),
                  Icon(trailingIcon, size: 20),
                ],
              ],
            ),
    );

    final button = switch (variant) {
      EvoButtonVariant.primary => FilledButton(
        onPressed: enabled ? onPressed : null,
        // Durante o carregamento mantém o preto (desabilitado, mas sem "apagar").
        style: isLoading
            ? FilledButton.styleFrom(
                disabledBackgroundColor: EvoColors.accent,
                disabledForegroundColor: EvoColors.onAccent,
              )
            : null,
        child: content,
      ),
      EvoButtonVariant.secondary => OutlinedButton(
        onPressed: enabled ? onPressed : null,
        child: content,
      ),
    };

    return EvoFocusRing(
      child: EvoPressable(enabled: enabled, child: button),
    );
  }
}

enum EvoButtonVariant { primary, secondary }
