import 'package:flutter/material.dart';

import '../../app/theme/tokens.g.dart';
import 'evo_pressable.dart';

/// Card padrão: superfície branca com borda sutil, sem sombra.
///
/// Com [onTap], responde ao toque encolhendo levemente.
class EvoCard extends StatelessWidget {
  const EvoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(EvoSpace.lg + 4),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    return onTap == null ? card : EvoPressable(pressedScale: 0.98, child: card);
  }
}
