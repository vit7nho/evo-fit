import 'package:flutter/material.dart';

import '../../app/theme/tokens.g.dart';

/// Contorno preto ao redor do filho quando ele recebe foco pelo teclado ou D-pad.
///
/// O destaque padrão do Material (10% de opacidade) some no preto e no branco da
/// identidade; este anel tem contraste máximo. No toque não aparece: só no modo de
/// navegação por teclado (FocusHighlightMode.traditional).
class EvoFocusRing extends StatefulWidget {
  const EvoFocusRing({
    super.key,
    required this.child,
    this.shape = const StadiumBorder(),
  });

  final Widget child;

  /// Forma do anel; acompanhe a forma do filho (pílula, cartão, círculo).
  final OutlinedBorder shape;

  @override
  State<EvoFocusRing> createState() => _EvoFocusRingState();
}

class _EvoFocusRingState extends State<EvoFocusRing> {
  bool _focused = false;

  bool get _keyboard =>
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onModeChanged);
    super.dispose();
  }

  void _onModeChanged(FocusHighlightMode _) {
    if (_focused && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Só observa o foco dos descendentes; não entra na ordem de navegação.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Stack(
        // Repassa as restrições do pai: um botão esticado continua esticado.
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_focused && _keyboard)
            Positioned.fill(
              left: -3,
              top: -3,
              right: -3,
              bottom: -3,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    shape: widget.shape.copyWith(
                      side: const BorderSide(color: EvoColors.accent, width: 2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
