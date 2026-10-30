import 'package:flutter/material.dart';

import '../../app/theme/tokens.g.dart';

/// Mensagem de erro de um formulário inteiro (ex.: "E-mail ou senha incorretos").
///
/// Anunciada por leitores de tela assim que aparece (live region).
class EvoFormError extends StatelessWidget {
  const EvoFormError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(EvoSpace.md),
        decoration: BoxDecoration(
          color: EvoColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(EvoRadius.input),
          border: Border.all(color: EvoColors.danger.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: EvoColors.danger,
              size: 20,
            ),
            const SizedBox(width: EvoSpace.sm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: EvoColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
