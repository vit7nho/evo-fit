import 'package:flutter/material.dart';

import '../../../app/theme/tokens.g.dart';
import '../domain/body.dart';

/// Renderer 2D do Meu Corpo (ADR-010, ADR-045). Só traduz `muscle_id` em região
/// visual: as cores vêm das faixas calculadas pela API, e trocar este desenho por
/// um 3D não muda nenhum cálculo.
///
/// As formas ficam numa caixa de [bodyMapSize] e são desenhadas com
/// `CustomPainter` (sem pacote de SVG): cada músculo é uma lista de pontos da
/// metade esquerda do corpo, espelhada e suavizada em curvas.
const bodyMapSize = Size(200, 440);

/// Escala e deslocamento que centralizam o mapa em [size] (também usado nos testes
/// para tocar num músculo).
({double scale, Offset offset}) bodyMapTransform(Size size) {
  final scale = [
    size.width / bodyMapSize.width,
    size.height / bodyMapSize.height,
  ].reduce((a, b) => a < b ? a : b);
  return (
    scale: scale,
    offset: Offset(
      (size.width - bodyMapSize.width * scale) / 2,
      (size.height - bodyMapSize.height * scale) / 2,
    ),
  );
}

typedef _Shape = List<Offset>;

_Shape _pts(List<double> xy) => [
  for (var i = 0; i < xy.length; i += 2) Offset(xy[i], xy[i + 1]),
];

_Shape _mirror(_Shape shape) => [
  for (final p in shape) Offset(bodyMapSize.width - p.dx, p.dy),
];

/// Curva fechada e suave pelos pontos (Catmull-Rom convertida em Bézier cúbica).
Path _smooth(_Shape p) {
  final path = Path()..moveTo(p[0].dx, p[0].dy);
  final n = p.length;
  for (var i = 0; i < n; i++) {
    final p0 = p[(i - 1 + n) % n];
    final p1 = p[i];
    final p2 = p[(i + 1) % n];
    final p3 = p[(i + 2) % n];
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path..close();
}

/// As duas metades (esquerda e espelhada) num só caminho.
Path _pair(_Shape left) => Path()
  ..addPath(_smooth(left), Offset.zero)
  ..addPath(_smooth(_mirror(left)), Offset.zero);

/// Forma que cruza o meio do corpo: a metade esquerda vai do topo ao fundo pelo
/// centro (x = 100) e o resto é o espelho, em ordem inversa.
Path _centered(_Shape left) =>
    _smooth([...left, ..._mirror(left).reversed.skip(1).take(left.length - 2)]);

// --- silhueta (neutra, não é músculo) ---

final _head = Path()
  ..addOval(
    Rect.fromCenter(center: const Offset(100, 30), width: 34, height: 42),
  );
final _neck = _smooth(_pts([92, 46, 108, 46, 110, 64, 90, 64]));
final _torso = _centered(
  _pts([
    100,
    60,
    84,
    62,
    62,
    70,
    50,
    82,
    54,
    112,
    62,
    150,
    68,
    196,
    64,
    230,
    100,
    240,
  ]),
);
final _limbs = <Path>[
  // braço
  _pair(_pts([52, 80, 40, 92, 34, 130, 34, 162, 48, 164, 58, 132, 60, 100])),
  // antebraço
  _pair(_pts([34, 158, 28, 200, 26, 232, 38, 236, 46, 200, 49, 162])),
  // mão
  _pair(_pts([26, 232, 24, 252, 32, 264, 40, 254, 38, 234])),
  // coxa
  _pair(_pts([66, 226, 62, 280, 66, 330, 82, 338, 96, 330, 99, 280, 100, 236])),
  // perna
  _pair(_pts([66, 328, 64, 372, 70, 414, 84, 416, 90, 372, 94, 332])),
  // pé
  _pair(_pts([70, 410, 62, 428, 70, 434, 88, 432, 86, 412])),
];

/// Desenhadas uma a uma: o espelho inverte o sentido da curva, e num caminho só
/// as sobreposições de sentidos opostos (tronco e coxa) virariam buracos.
final _silhouette = [_head, _neck, _torso, ..._limbs];

// --- músculos (IDs estáveis da API) ---

final _delts = _pair(
  _pts([64, 70, 52, 80, 45, 96, 48, 114, 57, 110, 64, 92, 76, 76]),
);
final _forearms = _pair(
  _pts([38, 166, 32, 198, 30, 226, 38, 228, 44, 200, 47, 168]),
);

/// Músculos da frente.
final Map<String, Path> frontMuscles = {
  'delts': _delts,
  'chest': _pair(_pts([98, 76, 78, 74, 66, 88, 63, 110, 76, 124, 98, 122])),
  'biceps': _pair(_pts([52, 110, 44, 124, 41, 148, 47, 158, 55, 148, 58, 122])),
  'forearms': _forearms,
  'abs': _centered(_pts([100, 126, 87, 128, 85, 162, 87, 200, 100, 216])),
  'obliques': _pair(
    _pts([83, 130, 70, 130, 66, 154, 70, 190, 83, 208, 84, 164]),
  ),
  'quads': _pair(
    _pts([70, 238, 66, 282, 70, 322, 84, 330, 94, 322, 97, 282, 94, 246]),
  ),
};

/// Músculos das costas (a figura vista de trás).
final Map<String, Path> backMuscles = {
  'traps': _centered(_pts([100, 54, 86, 64, 68, 72, 84, 86, 100, 122])),
  'delts': _delts,
  'lats': _pair(
    _pts([96, 126, 84, 96, 66, 100, 62, 124, 70, 168, 84, 186, 96, 196]),
  ),
  'triceps': _pair(
    _pts([52, 110, 44, 124, 41, 150, 47, 160, 55, 150, 58, 122]),
  ),
  'forearms': _forearms,
  'glutes': _pair(_pts([98, 206, 78, 206, 66, 224, 68, 252, 84, 262, 98, 254])),
  'hamstrings': _pair(
    _pts([68, 264, 66, 300, 72, 326, 84, 330, 94, 322, 96, 290, 94, 264]),
  ),
  'calves': _pair(_pts([70, 340, 66, 362, 70, 392, 80, 398, 88, 380, 90, 346])),
};

Map<String, Path> musclesOf(BodyView view) =>
    view == BodyView.front ? frontMuscles : backMuscles;

Color bandColor(StimulusBand band) => switch (band) {
  StimulusBand.none => EvoColors.stimulusNone,
  StimulusBand.low => EvoColors.stimulusLow,
  StimulusBand.mid => EvoColors.stimulusMid,
  StimulusBand.high => EvoColors.stimulusHigh,
};

/// O mapa de um lado do corpo: toque num músculo chama [onSelect] com o ID dele.
class BodyMap extends StatelessWidget {
  const BodyMap({
    super.key,
    required this.view,
    required this.bands,
    required this.onSelect,
    this.selected,
  });

  final BodyView view;

  /// Faixa de cada músculo (`muscle_id` → faixa); ausente = sem estímulo.
  final Map<String, StimulusBand> bands;
  final String? selected;
  final ValueChanged<String> onSelect;

  /// O músculo em [local] (coordenadas do widget de tamanho [size]), se houver.
  String? muscleAt(Offset local, Size size) {
    final t = bodyMapTransform(size);
    final point = (local - t.offset) / t.scale;
    for (final MapEntry(:key, :value) in musclesOf(view).entries) {
      if (value.contains(point)) return key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth,
          constraints.hasBoundedHeight
              ? constraints.maxHeight
              : constraints.maxWidth * bodyMapSize.height / bodyMapSize.width,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final muscle = muscleAt(details.localPosition, size);
            if (muscle != null) onSelect(muscle);
          },
          child: CustomPaint(
            size: size,
            painter: _BodyPainter(view: view, bands: bands, selected: selected),
          ),
        );
      },
    );
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({required this.view, required this.bands, this.selected});

  final BodyView view;
  final Map<String, StimulusBand> bands;
  final String? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final t = bodyMapTransform(size);
    canvas
      ..save()
      ..translate(t.offset.dx, t.offset.dy)
      ..scale(t.scale);
    final skin = Paint()..color = EvoColors.bgElevated;
    for (final part in _silhouette) {
      canvas.drawPath(part, skin);
    }
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = EvoColors.bgSurface;
    final muscles = musclesOf(view);
    for (final MapEntry(:key, :value) in muscles.entries) {
      final band = bands[key] ?? StimulusBand.none;
      canvas
        ..drawPath(value, Paint()..color = bandColor(band))
        ..drawPath(value, outline);
    }
    if (muscles[selected] case final path?) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = EvoColors.textPrimary,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.view != view || old.selected != selected || old.bands != bands;
}
