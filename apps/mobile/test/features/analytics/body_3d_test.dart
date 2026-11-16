import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/analytics/domain/body.dart';
import 'package:evofit/features/analytics/presentation/body_map.dart';
import 'package:evofit/features/analytics/presentation/body_model_3d.dart';
import 'package:evofit/features/sessions/data/session_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

/// O JSON do GLB (primeiro bloco do arquivo binário).
Map<String, dynamic> _gltf(Uint8List glb) {
  final data = ByteData.sublistView(glb);
  expect(String.fromCharCodes(glb.sublist(0, 4)), 'glTF');
  expect(data.getUint32(4, Endian.little), 2);
  expect(data.getUint32(8, Endian.little), glb.length);
  final length = data.getUint32(12, Endian.little);
  expect(String.fromCharCodes(glb.sublist(16, 20)), 'JSON');
  return jsonDecode(utf8.decode(glb.sublist(20, 20 + length)))
      as Map<String, dynamic>;
}

/// Renderer 3D falso: guarda o que recebeu e "toca" um músculo por botão.
class _Fake3d {
  Map<String, StimulusBand>? bands;
  String? selected;

  Widget build({
    required Map<String, StimulusBand> bands,
    required ValueChanged<String> onSelect,
    String? selected,
  }) {
    this.bands = bands;
    this.selected = selected;
    return Center(
      child: TextButton(
        onPressed: () => onSelect('glutes'),
        child: const Text('tocar glúteos no 3D'),
      ),
    );
  }
}

Future<FakeAuthServer> _pump(
  WidgetTester tester, {
  Body3dBuilder? Function()? renderer,
}) async {
  final server = FakeAuthServer(validRefreshToken: 'salvo')
    ..bodyPerWeek = {'chest': 7, 'glutes': 3};
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        httpClientAdapterProvider.overrideWithValue(server.adapter),
        draftStorageProvider.overrideWithValue(InMemoryDraftStorage()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage('salvo')),
        if (renderer != null) body3dProvider.overrideWithValue(renderer()),
      ],
      child: const EvoFitApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Meu Corpo'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Meu Corpo'));
  await tester.pumpAndSettle();
  return server;
}

void main() {
  test('o manequim tem um material por músculo do catálogo, mais a pele', () {
    final gltf = _gltf(File(bodyModelAsset).readAsBytesSync());
    final materials = [
      for (final m in gltf['materials'] as List) (m as Map)['name'] as String,
    ];
    expect(materials.toSet(), {
      'skin',
      for (final (id, _, _) in FakeAuthServer.muscleCatalog) id,
    });
    expect(materials, hasLength(14));
    // Os dois lados de um músculo dividem o material: pintar um pinta os dois.
    final nodes = [for (final n in gltf['nodes'] as List) (n as Map)['name']];
    expect(nodes, containsAll(['chest_r', 'chest_l', 'abs', 'traps']));
  });

  test('cores no espaço linear e o script de pintura', () {
    expect(linearColor(const Color(0xFFFFFFFF)), [1, 1, 1, 1]);
    expect(linearColor(const Color(0xFF000000)), [0, 0, 0, 1]);
    // sRGB 50% ≈ 21,4% linear (a curva do glTF, não uma conta proporcional).
    expect(linearColor(const Color(0xFF808080))[0], closeTo(0.2159, 0.0005));

    final colors = materialColors({
      'chest': StimulusBand.mid,
    }, selected: 'chest');
    expect(colors.keys.toSet(), {
      for (final (id, _, _) in FakeAuthServer.muscleCatalog) id,
    });
    expect(colors['calves'], linearColor(bandColor(StimulusBand.none)));
    // O selecionado fica mais escuro, como o contorno do 2D.
    expect(
      colors['chest']![0],
      closeTo(linearColor(bandColor(StimulusBand.mid))[0] * 0.55, 0.0001),
    );

    final script = bodyModelScript(colors);
    expect(script, contains(jsonEncode(colors)));
    expect(script, contains('EvoBody.postMessage(m.name)'));
    expect(script, contains('materialFromPoint'));
  });

  testWidgets('o 3D recebe as faixas e o toque abre o detalhe do músculo', (
    tester,
  ) async {
    final fake = _Fake3d();
    final server = await _pump(tester, renderer: () => fake.build);

    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('body-map')), findsNothing);
    expect(fake.bands!['chest'], StimulusBand.mid);
    expect(fake.bands!['glutes'], StimulusBand.low);
    expect(find.textContaining('Prova de conceito'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^Manequim 3D do corpo: ')),
      findsOneWidget,
    );

    await tester.tap(find.text('tocar glúteos no 3D'));
    await tester.pumpAndSettle();
    expect(server.analyticsQueries.last, startsWith('glutes?'));
    expect(fake.selected, 'glutes');
    expect(find.text('Glúteos'), findsWidgets);

    // Fechar o detalhe e voltar ao 2D: o mapa volta, do lado da frente.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(fake.selected, isNull);
    await tester.tap(find.text('Frente'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('body-map')), findsOneWidget);
  });

  testWidgets('sem renderer 3D na plataforma, não há a opção 3D', (
    tester,
  ) async {
    await _pump(tester, renderer: () => null);
    expect(find.text('Frente'), findsOneWidget);
    expect(find.text('3D'), findsNothing);
  });
}
