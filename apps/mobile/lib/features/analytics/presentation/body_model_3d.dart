import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/theme/tokens.g.dart';
import '../domain/body.dart';
import 'body_map.dart';

/// Renderer 3D do Meu Corpo — prova de conceito da etapa 3.9 (ADR-048).
///
/// O mesmo contrato do mapa 2D (ADR-010): recebe a faixa de cada `muscle_id` e
/// devolve o músculo tocado. O manequim (`assets/body3d/body.glb`, gerado por
/// `tools/body3d/make_body_glb.py`) tem um material por músculo com o nome do
/// `muscle_id`; o `model-viewer` (WebView, JavaScript empacotado, sem internet)
/// pinta esses materiais e responde qual deles foi tocado.
typedef Body3dBuilder = Widget Function({
  required Map<String, StimulusBand> bands,
  required ValueChanged<String> onSelect,
  String? selected,
});

/// O renderer 3D disponível nesta plataforma (nulo = só o 2D). Só Android: o
/// `model_viewer_plus` usa WebView. Os testes trocam por um falso.
final body3dProvider = Provider<Body3dBuilder?>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? ({required bands, required onSelect, selected}) =>
            BodyModel3D(bands: bands, selected: selected, onSelect: onSelect)
      : null,
);

const bodyModelAsset = 'assets/body3d/body.glb';

/// Cor da faixa no espaço linear do glTF (`baseColorFactor`): o sRGB da paleta
/// convertido, para o 3D mostrar as mesmas cores do mapa 2D.
List<double> linearColor(Color color, {double shade = 1}) {
  // Conversão sRGB → linear padrão (IEC 61966-2-1).
  double linear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return [
    for (final c in [color.r, color.g, color.b])
      double.parse((linear(c) * shade).toStringAsFixed(4)),
    1,
  ];
}

/// Cores de cada material: a faixa do músculo (ausente = sem estímulo); o
/// selecionado fica mais escuro, como o contorno do 2D.
Map<String, List<double>> materialColors(
  Map<String, StimulusBand> bands, {
  String? selected,
}) => {
  for (final id in {...frontMuscles.keys, ...backMuscles.keys})
    id: linearColor(
      bandColor(bands[id] ?? StimulusBand.none),
      shade: id == selected ? 0.55 : 1,
    ),
};

/// Pinta os materiais quando o modelo carrega (e de novo a cada `evoPaint`) e
/// manda pelo canal `EvoBody` o material tocado — só toque, não o fim de um giro.
String bodyModelScript(Map<String, List<double>> colors) =>
    '''
(function () {
  var colors = ${jsonEncode(colors)};
  var down = null;
  function viewer() { return document.querySelector('#evo-body'); }
  function apply() {
    var v = viewer();
    if (!v || !v.model) return;
    v.model.materials.forEach(function (m) {
      var c = colors[m.name];
      if (c) m.pbrMetallicRoughness.setBaseColorFactor(c);
    });
  }
  window.evoPaint = function (c) { colors = c; apply(); };
  function wire() {
    var v = viewer();
    if (!v) { setTimeout(wire, 50); return; }
    v.addEventListener('load', apply);
    v.addEventListener('pointerdown', function (e) { down = [e.clientX, e.clientY]; });
    v.addEventListener('click', function (e) {
      var moved = down && Math.abs(e.clientX - down[0]) + Math.abs(e.clientY - down[1]) > 12;
      down = null;
      if (moved) return;
      var m = v.materialFromPoint(e.clientX, e.clientY);
      if (m && colors[m.name] && window.EvoBody) EvoBody.postMessage(m.name);
    });
    apply();
  }
  wire();
})();
''';

class BodyModel3D extends StatefulWidget {
  const BodyModel3D({
    super.key,
    required this.bands,
    required this.onSelect,
    this.selected,
  });

  final Map<String, StimulusBand> bands;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  State<BodyModel3D> createState() => _BodyModel3DState();
}

class _BodyModel3DState extends State<BodyModel3D> {
  WebViewController? _controller;

  // O HTML da página fica fixo (com as cores do primeiro desenho); mudanças de
  // faixa ou de seleção repintam por JavaScript, sem recarregar o modelo.
  late final String _script = bodyModelScript(
    materialColors(widget.bands, selected: widget.selected),
  );

  @override
  void didUpdateWidget(BodyModel3D old) {
    super.didUpdateWidget(old);
    if (!mapEquals(old.bands, widget.bands) ||
        old.selected != widget.selected) {
      final colors = jsonEncode(
        materialColors(widget.bands, selected: widget.selected),
      );
      _controller?.runJavaScript('window.evoPaint && window.evoPaint($colors)');
    }
  }

  @override
  Widget build(BuildContext context) => ModelViewer(
    id: 'evo-body',
    src: bodyModelAsset,
    alt: 'Manequim 3D com os músculos coloridos pela faixa de estímulo',
    backgroundColor: EvoColors.bgSurface,
    cameraControls: true,
    disablePan: true,
    // Arrastar na vertical rola a tela; na horizontal gira o corpo.
    touchAction: TouchAction.panY,
    interactionPrompt: InteractionPrompt.none,
    cameraOrbit: '0deg 80deg auto',
    shadowIntensity: 0,
    exposure: 1,
    ar: false,
    debugLogging: false,
    relatedJs: _script,
    javascriptChannels: {
      JavascriptChannel(
        'EvoBody',
        onMessageReceived: (message) => widget.onSelect(message.message),
      ),
    },
    onWebViewCreated: (controller) => _controller = controller,
  );
}
