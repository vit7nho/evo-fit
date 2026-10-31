import 'package:flutter/material.dart';

import '../../app/theme/tokens.g.dart';

/// Marca do EvoFit: monograma preto (seta de evolução) + nome.
class EvoLogo extends StatelessWidget {
  const EvoLogo({super.key, this.size = 40, this.showName = true});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: EvoColors.accent,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        Icons.north_east_rounded,
        color: EvoColors.onAccent,
        size: size * 0.55,
      ),
    );
    if (!showName) return Semantics(label: 'EvoFit', child: mark);

    return Semantics(
      label: 'EvoFit',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          SizedBox(width: size * 0.3),
          Text(
            'EvoFit',
            // É uma marca, não um texto corrido: cresce pouco com a fonte do
            // sistema para não estourar a barra do topo em telas estreitas.
            textScaler: MediaQuery.textScalerOf(context)
                .clamp(maxScaleFactor: 1.2),
            style: TextStyle(
              color: EvoColors.textPrimary,
              fontSize: size * 0.55,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
        ],
      ),
    );
  }
}
