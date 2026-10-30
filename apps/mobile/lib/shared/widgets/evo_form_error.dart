import 'package:flutter/material.dart';

import '../../app/theme/motion.dart';
import '../../app/theme/tokens.g.dart';

/// Mensagem de erro de um formulário inteiro (ex.: "E-mail ou senha incorretos").
///
/// Com [message] nulo não ocupa espaço; ao aparecer ou sumir, o formulário abre e
/// fecha o espaço suavemente. Anunciada por leitores de tela assim que aparece.
class EvoFormError extends StatelessWidget {
  const EvoFormError({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    return AnimatedSize(
      duration: EvoMotion.base,
      curve: EvoCurves.standard,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: EvoMotion.base,
        child: text == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                key: ValueKey(text),
                padding: const EdgeInsets.only(bottom: EvoSpace.lg),
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: EvoSpace.lg,
                      vertical: EvoSpace.md,
                    ),
                    decoration: BoxDecoration(
                      color: EvoColors.danger.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(EvoRadius.input),
                      border: Border.all(
                        color: EvoColors.danger.withValues(alpha: 0.35),
                      ),
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
                            text,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: EvoColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
