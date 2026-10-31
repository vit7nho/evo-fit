import 'package:flutter/material.dart';

import '../../app/theme/motion.dart';
import '../../app/theme/tokens.g.dart';
import 'evo_focus_ring.dart';
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
      child: EvoFocusRing(
        child: EvoPressable(
          enabled: onTap != null,
          child: _SelectionFill(
            selected: selected,
            shape: const StadiumBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              splashColor: _splash(selected),
              highlightColor: _splash(selected),
              child: Container(
                constraints: const BoxConstraints(minHeight: evoTouchTargetMin),
                padding: const EdgeInsets.symmetric(horizontal: EvoSpace.lg),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // O ícone de marcado não depende de cor nem de animação.
                    EvoAnimatedSize(
                      duration: EvoMotion.fast,
                      child: selected
                          ? Padding(
                              padding: const EdgeInsets.only(
                                right: EvoSpace.xs,
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: foreground,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    // Com fonte grande o rótulo quebra linha em vez de estourar.
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: EvoSpace.sm,
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: foreground,
                            fontSize: EvoFontSize.bodySm,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Efeito de toque visível no branco (preto translúcido) e no preto (branco).
Color _splash(bool selected) =>
    (selected ? EvoColors.onAccent : EvoColors.accent).withValues(alpha: 0.12);

/// Fundo e contorno de um item selecionável, pintados no Material com [Ink] para
/// que o efeito de toque e o destaque do InkWell apareçam por cima (com um
/// fundo opaco por cima do Material, eles ficariam escondidos).
class _SelectionFill extends StatelessWidget {
  const _SelectionFill({
    required this.selected,
    required this.shape,
    required this.child,
  });

  final bool selected;
  final OutlinedBorder shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: selected ? 1 : 0),
        duration: evoDuration(context, EvoMotion.fast),
        curve: EvoCurves.standard,
        child: child,
        builder: (context, t, child) => Ink(
          decoration: ShapeDecoration(
            color: Color.lerp(EvoColors.bgSurface, EvoColors.accent, t),
            shape: shape.copyWith(
              side: BorderSide(
                color: Color.lerp(EvoColors.borderStrong, EvoColors.accent, t)!,
              ),
            ),
          ),
          child: child,
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

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(EvoRadius.card)),
  );

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? EvoColors.onAccent : EvoColors.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      child: EvoFocusRing(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(EvoRadius.card + 3)),
        ),
        child: EvoPressable(
          child: _SelectionFill(
            selected: selected,
            shape: _shape,
            child: InkWell(
              onTap: onTap,
              customBorder: _shape,
              splashColor: _splash(selected),
              highlightColor: _splash(selected),
              child: Container(
                constraints: const BoxConstraints(minHeight: 108),
                padding: const EdgeInsets.all(EvoSpace.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(icon, size: 26, color: foreground),
                        if (selected)
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: EvoColors.onAccent,
                          ),
                      ],
                    ),
                    const SizedBox(height: EvoSpace.lg),
                    Text(
                      label,
                      style: TextStyle(
                        color: foreground,
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
          Expanded(
            // A ação fica no nó de acessibilidade (o TalkBack ativa com dois
            // toques) e a célula inteira recebe o toque (≥ 48 dp de altura).
            child: Semantics(
              button: true,
              selected: value == n,
              label: '$n $semanticsSuffix',
              excludeSemantics: true,
              onTap: () => onChanged(n),
              child: EvoFocusRing(
                shape: const CircleBorder(),
                child: InkResponse(
                  onTap: () => onChanged(n),
                  radius: 28,
                  splashColor: _splash(false),
                  highlightColor: const Color(0x00000000),
                  child: SizedBox(
                    height: 56,
                    child: Center(
                      child: AnimatedContainer(
                        duration: evoDuration(context, EvoMotion.fast),
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
                          // O círculo tem tamanho fixo; o número cresce até onde cabe.
                          textScaler: MediaQuery.textScalerOf(context)
                              .clamp(maxScaleFactor: 1.3),
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
          Semantics(
            header: true,
            child: Text(text, style: theme.textTheme.titleMedium),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
