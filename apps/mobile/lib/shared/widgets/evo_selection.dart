import 'package:flutter/material.dart';

import '../../app/theme/motion.dart';
import '../../app/theme/tokens.g.dart';
import 'evo_pressable.dart';

/// Pílula selecionável: branca com contorno; preta quando selecionada.
class EvoChip extends StatelessWidget {
  const EvoChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? EvoColors.onAccent : EvoColors.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      child: EvoPressable(
        enabled: onTap != null,
        pressedScale: 0.95,
        child: Material(
          color: const Color(0x00000000),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: AnimatedContainer(
              duration: EvoMotion.fast,
              curve: EvoCurves.standard,
              constraints: const BoxConstraints(minHeight: evoTouchTargetMin),
              padding: const EdgeInsets.symmetric(horizontal: EvoSpace.lg),
              decoration: ShapeDecoration(
                color: selected ? EvoColors.accent : EvoColors.bgSurface,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: selected ? EvoColors.accent : EvoColors.borderStrong,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: EvoMotion.fast,
                    curve: EvoCurves.standard,
                    child: selected
                        ? Padding(
                            padding: const EdgeInsets.only(right: EvoSpace.xs),
                            child: Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: foreground,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: EvoFontSize.bodySm,
                      fontWeight: FontWeight.w600,
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

/// Grupo de pílulas para escolher vários (ou um, com [single]).
class EvoChipGroup extends StatelessWidget {
  const EvoChipGroup({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.single = false,
    this.enabled = true,
  });

  /// Pares (código, rótulo) na ordem de exibição.
  final List<(String, String)> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool single;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: EvoSpace.sm,
      runSpacing: EvoSpace.sm,
      children: [
        for (final (code, label) in options)
          EvoChip(
            label: label,
            selected: selected.contains(code),
            onTap: !enabled
                ? null
                : () {
                    if (single) {
                      onChanged({code});
                    } else {
                      final next = {...selected};
                      next.contains(code) ? next.remove(code) : next.add(code);
                      onChanged(next);
                    }
                  },
          ),
      ],
    );
  }
}

/// Cartão grande de escolha única (ex.: objetivo principal), com ícone.
class EvoOptionCard extends StatelessWidget {
  const EvoOptionCard({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: EvoPressable(
        pressedScale: 0.97,
        child: Material(
          color: const Color(0x00000000),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(EvoRadius.card),
            child: AnimatedContainer(
              duration: EvoMotion.fast,
              curve: EvoCurves.standard,
              constraints: const BoxConstraints(minHeight: 108),
              padding: const EdgeInsets.all(EvoSpace.lg),
              decoration: BoxDecoration(
                color: selected ? EvoColors.accent : EvoColors.bgSurface,
                borderRadius: BorderRadius.circular(EvoRadius.card),
                border: Border.all(
                  color: selected ? EvoColors.accent : EvoColors.borderSubtle,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(
                        icon,
                        size: 26,
                        color: selected
                            ? EvoColors.onAccent
                            : EvoColors.textPrimary,
                      ),
                      AnimatedOpacity(
                        opacity: selected ? 1 : 0,
                        duration: EvoMotion.fast,
                        child: const Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: EvoColors.onAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: EvoSpace.lg),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? EvoColors.onAccent
                          : EvoColors.textPrimary,
                      fontSize: EvoFontSize.bodySm,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
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

/// Fileira de números em círculos (ex.: dias por semana, 1 a 7).
class EvoNumberPicker extends StatelessWidget {
  const EvoNumberPicker({
    super.key,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    required this.semanticsSuffix,
  });

  final int min;
  final int max;
  final int? value;
  final ValueChanged<int> onChanged;

  /// Completa o rótulo lido por leitores de tela (ex.: "dias por semana").
  final String semanticsSuffix;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var n = min; n <= max; n++)
          // A célula inteira recebe o toque (≥ 48 dp); o círculo é só o desenho.
          Expanded(
            child: Semantics(
              button: true,
              selected: value == n,
              label: '$n $semanticsSuffix',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(n),
                child: SizedBox(
                  height: 56,
                  child: Center(
                    child: EvoPressable(
                      pressedScale: 0.9,
                      child: AnimatedContainer(
                        duration: EvoMotion.fast,
                        curve: EvoCurves.standard,
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: value == n
                              ? EvoColors.accent
                              : EvoColors.bgSurface,
                          border: Border.all(
                            color: value == n
                                ? EvoColors.accent
                                : EvoColors.borderStrong,
                          ),
                        ),
                        child: Text(
                          '$n',
                          style: TextStyle(
                            color: value == n
                                ? EvoColors.onAccent
                                : EvoColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Título de um bloco dentro de um formulário.
class EvoFieldLabel extends StatelessWidget {
  const EvoFieldLabel(this.text, {super.key, this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: EvoSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: theme.textTheme.titleMedium),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
