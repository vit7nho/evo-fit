import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/analytics/domain/analytics.dart' show apiDate;
import 'package:evofit/features/nutrition/domain/nutrition.dart';
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

Future<void> _openNutrition(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Nutrição'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await _tap(tester, find.text('Nutrição'));
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

void main() {
  testWidgets('sem consentimento de saúde, autoriza antes de registrar', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester, consented: false);
    await _openNutrition(tester);

    expect(find.text('Autorize o uso de dados de saúde'), findsOneWidget);
    expect(find.text('Registrar refeição'), findsNothing);
    await _tap(tester, find.text('Autorizar e continuar'));

    expect(server.consentCalls, ['PUT health_data']);
    expect(find.text('Nenhuma refeição neste dia'), findsOneWidget);
    // O "hoje" vem da API (o fuso do perfil), não do aparelho.
    expect(server.dailyQueries, ['hoje']);
  });

  testWidgets('registra uma refeição com um alimento criado na hora', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _openNutrition(tester);
    await _tap(tester, find.text('Registrar refeição').first);
    await _tap(tester, find.text('Almoço'));

    // Sem alimentos ainda: cria um com os valores da embalagem.
    await _tap(tester, find.text('Adicionar alimento'));
    expect(find.text('Nenhum alimento ainda'), findsOneWidget);
    await _tap(tester, find.text('Criar alimento').first);
    await tester.enterText(
      find.widgetWithText(TextField, 'Nome'),
      'Frango grelhado',
    );
    for (final (label, value) in [
      ('Calorias (kcal)', '159'),
      ('Proteína (g)', '32'),
      ('Carboidratos (g)', '0'),
      ('Gordura (g)', '2,5'),
    ]) {
      await tester.enterText(find.widgetWithText(TextField, label), value);
    }
    await _tap(tester, find.text('Salvar alimento'));
    expect(server.foods.single['fat_g'], 2.5);
    expect(server.foods.single.containsKey('fiber_g'), isTrue);

    // De volta à refeição: 100 g por padrão; 120 g mudam a prévia.
    expect(find.text('Frango grelhado'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Gramas de Frango grelhado'),
      '120',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Total: 191 kcal · P 38,4 g · C 0 g · G 3 g'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Salvar refeição'));

    final body = server.mealBodies.single;
    expect(body['meal_type'], 'lunch');
    expect(body['items'], [
      {'food_id': 'alimento-1', 'quantity_g': 120.0},
    ]);
    // O dia mostra a refeição e os totais gravados pela API.
    expect(
      find.textContaining('Frango grelhado · 120 g · 191 kcal'),
      findsOneWidget,
    );
    expect(find.text('191 kcal'), findsWidgets);
    expect(find.text('38,4 g'), findsOneWidget);
  });

  testWidgets('busca no catálogo, mostra a fonte e usa a porção comum', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) => s.foods.addAll([
        FakeAuthServer.catalogFood('arroz', 'Arroz branco cozido'),
        FakeAuthServer.catalogFood(
          'pao',
          'Pão francês',
          kcal: 300,
          portion: 50,
        ),
      ]),
    );
    await _openNutrition(tester);
    await _tap(tester, find.text('Registrar refeição').first);
    await _tap(tester, find.text('Adicionar alimento'));
    await tester.enterText(find.byType(TextField), 'pao');
    await tester.pumpAndSettle();

    expect(find.text('Arroz branco cozido'), findsNothing);
    expect(
      find.text('300 kcal por 100 g · Fonte: TACO (NEPA/UNICAMP)'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Pão francês'));
    final grams = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Gramas de Pão francês'),
    );
    expect(grams.controller!.text, '50');
    await _tap(tester, find.text('Salvar refeição'));
    expect(server.meals, hasLength(1));
  });

  testWidgets('edita e apaga uma refeição; navega entre os dias', (
    tester,
  ) async {
    final today = _today();
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) {
        s.foods.add(FakeAuthServer.catalogFood('arroz', 'Arroz branco cozido'));
      },
    );
    await _openNutrition(tester);
    await _tap(tester, find.text('Registrar refeição').first);
    await _tap(tester, find.text('Adicionar alimento'));
    await _tap(tester, find.text('Arroz branco cozido'));
    await _tap(tester, find.text('Salvar refeição'));
    expect(
      find.textContaining('Arroz branco cozido · 150 g · 192 kcal'),
      findsOneWidget,
    );

    // Editar: a quantidade muda e a refeição é regravada (PUT).
    await _tap(tester, find.textContaining('Arroz branco cozido · 150 g'));
    expect(find.text('Editar refeição'), findsOneWidget);
    // A prévia da edição parte dos valores gravados (150 g de arroz = 192 kcal).
    expect(
      find.text('Total: 192 kcal · P 3,8 g · C 42,2 g · G 0,3 g'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Gramas de Arroz branco cozido'),
      '200',
    );
    await _tap(tester, find.text('Salvar refeição'));
    expect(server.meals, hasLength(1));
    expect(find.textContaining('200 g · 256 kcal'), findsOneWidget);

    // Dia anterior vazio; o seguinte a hoje não existe.
    await _tap(tester, find.byTooltip('Dia anterior'));
    expect(
      server.dailyQueries.last,
      apiDate(today.subtract(const Duration(days: 1))),
    );
    expect(find.text('Nenhuma refeição neste dia'), findsOneWidget);
    await _tap(tester, find.byTooltip('Dia seguinte'));
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
    );
    expect(next.onPressed, isNull);

    // Apagar pede confirmação.
    await _tap(tester, find.textContaining('200 g · 256 kcal'));
    await _tap(tester, find.byTooltip('Apagar refeição'));
    await _tap(tester, find.text('Apagar'));
    expect(server.meals, isEmpty);
    expect(find.text('Nenhuma refeição neste dia'), findsOneWidget);
  });

  test('regras de cálculo e formatação', () {
    const per100 = Nutrients(
      kcal: 128,
      proteinG: 2.5,
      carbsG: 28.1,
      fatG: 0.2,
      fiberG: 1.6,
    );
    final portion = per100.scaled(150);
    expect(
      (portion.kcal, portion.proteinG, portion.carbsG, portion.fiberG),
      (192.0, 3.8, 42.2, 2.4),
    );
    expect(formatGrams(12.0), '12');
    expect(formatGrams(12.25), '12,3');
    expect(
      (const Nutrients(kcal: 1, proteinG: 1, carbsG: 1, fatG: 1) +
              const Nutrients(kcal: 1, proteinG: 1, carbsG: 1, fatG: 1))
          .fiberG,
      isNull,
    );
    expect(describeMacros(portion), 'P 3,8 g · C 42,2 g · G 0,3 g');
  });
}
