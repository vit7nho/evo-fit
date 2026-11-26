import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/measurements/domain/measurements.dart';
import 'package:evofit/features/measurements/presentation/measurements_page.dart';
import 'package:evofit/features/sessions/data/session_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

Future<FakeAuthServer> _pumpSignedIn(
  WidgetTester tester, {
  bool consented = true,
  void Function(FakeAuthServer server)? setUp,
}) async {
  final server = FakeAuthServer(validRefreshToken: 'salvo');
  if (consented) server.consents.add('health_data');
  setUp?.call(server);
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
      ],
      child: const EvoFitApp(),
    ),
  );
  await tester.pumpAndSettle();
  return server;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Peso e medidas'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await _tap(tester, find.text('Peso e medidas'));
}

/// "2026-11-20T07:00:00", [daysAgo] dias antes de hoje.
String _at(int daysAgo, {int hour = 7}) {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day - daysAgo, hour);
  return day.toIso8601String().substring(0, 19);
}

Map<String, Object?> _measurement(
  String id,
  String at, {
  num? weight,
  num? waist,
}) => {
  'id': id,
  'measured_at': at,
  'local_time': at,
  'weight_kg': weight,
  'body_fat_pct': null,
  'waist_cm': waist,
  'notes': null,
};

void main() {
  testWidgets('sem consentimento de saúde, autoriza antes de registrar', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester, consented: false);
    await _open(tester);

    expect(find.text('Autorize o uso de dados de saúde'), findsOneWidget);
    expect(find.text('Registrar medida'), findsNothing);
    await _tap(tester, find.text('Autorizar e continuar'));

    expect(server.consentCalls, ['PUT health_data']);
    expect(find.text('Nenhuma medida neste período'), findsOneWidget);
  });

  testWidgets('o botão Salvar medida fica à vista, sem rolar (piloto 5.7)', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _open(tester);
    await _tap(tester, find.text('Registrar medida').first);

    // O botão fica no rodapé, fora da lista que rola: à vista em qualquer
    // tela, sem passar pelas medidas vazias.
    expect(
      find.ancestor(
        of: find.text('Salvar medida'),
        matching: find.byType(ListView),
      ),
      findsNothing,
    );
    expect(find.text('Salvar medida').hitTestable(), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Peso'), '72,4');
    await tester.tap(find.text('Salvar medida'));
    await tester.pumpAndSettle();
    expect(server.measurementBodies.single['weight_kg'], 72.4);
  });

  testWidgets('registra o peso e a cintura; a tendência aparece', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) {
        s.measurements.add(_measurement('m1', _at(20), weight: 80));
        s.trendWeeklyRate = -0.5;
      },
    );
    await _open(tester);
    // Um ponto só: ainda sem tendência.
    expect(find.text('80 kg'), findsOneWidget);
    expect(
      find.text('Registre mais vezes para ver a tendência.'),
      findsOneWidget,
    );

    await _tap(tester, find.text('Registrar medida').first);
    await tester.enterText(find.widgetWithText(TextField, 'Peso'), '78,5');
    await tester.enterText(find.widgetWithText(TextField, 'Cintura'), '84');
    await _tap(tester, find.text('Salvar medida'));

    final body = server.measurementBodies.single;
    expect(body['weight_kg'], 78.5);
    expect(body['waist_cm'], 84.0);
    expect(body['body_fat_pct'], isNull);
    // Sem escolher a hora: o instante de agora, em UTC (certo em qualquer fuso).
    expect(body['measured_at'], endsWith('Z'));

    // De volta: a variação, o ritmo e as duas medidas como chips.
    expect(find.text('78,5 kg'), findsOneWidget);
    expect(find.textContaining('−1,5 kg desde'), findsOneWidget);
    expect(find.text('Ritmo: −0,5 kg por semana'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Cintura'), findsOneWidget);
    expect(find.text('Peso 78,5 kg · Cintura 84 cm'), findsOneWidget);

    await _tap(tester, find.widgetWithText(ChoiceChip, 'Cintura'));
    expect(find.text('84 cm'), findsOneWidget);
  });

  testWidgets('limites e medida vazia conferidos no app', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _open(tester);
    await _tap(tester, find.text('Registrar medida').first);

    await _tap(tester, find.text('Salvar medida'));
    expect(find.text('Informe ao menos uma medida.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Peso'), '500');
    await _tap(tester, find.text('Salvar medida'));
    expect(find.text('Entre 20 e 350 kg.'), findsOneWidget);
    expect(server.measurementBodies, isEmpty);
    // Gordura corporal é rotulada como estimativa.
    expect(
      find.text('Estimativa da balança ou das dobras cutâneas'),
      findsOneWidget,
    );
  });

  testWidgets('edita e apaga uma medida', (tester) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) =>
          s.measurements.add(_measurement('m1', _at(3), weight: 72, waist: 80)),
    );
    await _open(tester);
    await _tap(tester, find.text('Peso 72 kg · Cintura 80 cm'));
    expect(find.text('Editar medida'), findsOneWidget);

    // Limpar a cintura manda nulo (a API limpa o campo).
    await tester.enterText(find.widgetWithText(TextField, 'Cintura'), '');
    await tester.enterText(find.widgetWithText(TextField, 'Peso'), '71,8');
    await _tap(tester, find.text('Salvar medida'));
    expect(server.measurementBodies.single['weight_kg'], 71.8);
    expect(server.measurementBodies.single['waist_cm'], isNull);
    // Na edição, o horário mostrado (do perfil), sem fuso.
    expect(server.measurementBodies.single['measured_at'], _at(3));
    expect(find.text('Peso 71,8 kg'), findsOneWidget);

    await _tap(tester, find.text('Peso 71,8 kg'));
    await _tap(tester, find.text('Apagar medida'));
    expect(find.text('Apagar medida?'), findsOneWidget);
    await _tap(tester, find.text('Apagar'));
    expect(server.measurements, isEmpty);
    expect(find.text('Nenhuma medida neste período'), findsOneWidget);
  });

  test('formatação das medidas', () {
    expect(formatMeasure(72.44, 'kg'), '72,4 kg');
    expect(formatMeasure(81, 'cm'), '81 cm');
    expect(formatChange(-1.25, 'kg'), '−1,3 kg');
    expect(formatChange(0.4, 'cm'), '+0,4 cm');
    expect(formatChange(0.02, 'kg'), '0 kg');
    expect(periodLabel(30), '30 dias');
    expect(periodLabel(180), '6 meses');
    expect(periodLabel(365), '1 ano');
    const labels = {
      'weight_kg': MetricInfo(
        metric: 'weight_kg',
        label: 'Peso',
        unit: 'kg',
        min: 20,
        max: 350,
      ),
    };
    expect(describeValues({'weight_kg': 70.5}, labels), 'Peso 70,5 kg');
  });
}
