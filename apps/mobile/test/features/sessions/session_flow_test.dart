import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/sessions/application/session_controller.dart';
import 'package:evofit/shared/widgets/evo_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

/// Ficha com um exercício avulso (descanso 90 s) e um bi-set (descanso 60 s após a rodada).
Map<String, Object?> _template(FakeAuthServer s) =>
    s.templateFrom('ficha-a', 1, {
      'name': 'Treino A',
      'notes': null,
      'groups': [
        {'kind': 'biset', 'rest_after_s': 60},
      ],
      'items': [
        {
          'exercise_id': 'ex-supino',
          'planned_sets': [
            for (var i = 0; i < 3; i++)
              {'kind': 'working', 'reps_min': 8, 'reps_max': 12},
          ],
          'rest_s': 90,
          'notes': null,
          'group': null,
        },
        for (final id in ['ex-triceps', 'ex-agachamento'])
          {
            'exercise_id': id,
            'planned_sets': [
              {'kind': 'working', 'reps_min': 12, 'reps_max': 12},
            ],
            'rest_s': null,
            'notes': null,
            'group': 0,
          },
      ],
    });

Future<FakeAuthServer> _pumpSignedIn(
  WidgetTester tester, {
  void Function(FakeAuthServer server)? setUp,
}) async {
  final server = FakeAuthServer(validRefreshToken: 'salvo');
  server.templates = [_template(server)];
  setUp?.call(server);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        httpClientAdapterProvider.overrideWithValue(server.adapter),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage('salvo')),
        // Sem tique: o relógio que avança sozinho impediria a tela de assentar.
        clockTickProvider.overrideWith((ref) => const Stream.empty()),
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

Future<void> _startTemplate(WidgetTester tester) async {
  await _tap(tester, find.text('Fichas de treino'));
  await _tap(tester, find.byTooltip('Iniciar Treino A'));
}

Finder _check(int set, [String exercise = 'Supino reto com barra']) =>
    find.byTooltip('Concluir série $set de $exercise');

void main() {
  testWidgets('um toque no ✓ registra a série com os valores da última vez', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) => s.previousSets = {
        'ex-supino': [
          {'kind': 'working', 'reps': 10, 'load_kg': 60, 'duration_s': null},
          {'kind': 'working', 'reps': 8, 'load_kg': 62.5, 'duration_s': null},
        ],
      },
    );
    await _startTemplate(tester);

    expect(find.text('Treino A'), findsOneWidget);
    expect(find.text('Última vez: 60 kg × 10, 62,5 kg × 8'), findsOneWidget);
    await _tap(tester, _check(1));

    expect(server.setBodies.single, {
      'kind': 'working',
      'reps': 10,
      'load_kg': 60.0,
    });
    expect(
      find.bySemanticsLabel('Série 1 feita: 60 kg × 10. Toque para corrigir.'),
      findsOneWidget,
    );
    // Descanso do exercício avulso.
    expect(find.text('Descanso 01:30'), findsOneWidget);

    // A próxima linha sugere a segunda série da última vez.
    await _tap(tester, _check(2));
    expect(server.setBodies.last, {
      'kind': 'working',
      'reps': 8,
      'load_kg': 62.5,
    });
  });

  testWidgets('o digitado vale mais que a sugestão; aquecimento num toque', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _startTemplate(tester);

    await _tap(
      tester,
      find.bySemanticsLabel(
        'Série 1 de Supino reto com barra, válida. Toque para marcar como aquecimento.',
      ),
    );
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '20');
    await tester.enterText(fields.at(1), '15');
    await _tap(tester, _check(1));

    expect(server.setBodies.single, {
      'kind': 'warmup',
      'reps': 15,
      'load_kg': 20.0,
    });
  });

  testWidgets('no bi-set, o descanso só começa no fim da rodada', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    await _startTemplate(tester);
    expect(find.text('Bi-set · descanso 1 min após a rodada'), findsOneWidget);

    // Tríceps (1º do bi-set): sem descanso.
    await _tap(tester, _check(1, 'Tríceps francês'));
    expect(find.textContaining('Descanso'), findsNothing);

    // Agachamento (último do bi-set): descanso do grupo.
    await _tap(tester, _check(1, 'Agachamento livre'));
    expect(find.text('Descanso 01:00'), findsOneWidget);

    await _tap(tester, find.bySemanticsLabel('Mais 15 segundos'));
    expect(find.text('Descanso 01:15'), findsOneWidget);
    await _tap(tester, find.text('Pular'));
    expect(find.textContaining('Descanso'), findsNothing);
  });

  testWidgets(
    'falha ao salvar: o erro fica na linha e dá para tentar de novo',
    (tester) async {
      final server = await _pumpSignedIn(
        tester,
        setUp: (s) => s.failNextSet = true,
      );
      await _startTemplate(tester);

      await _tap(tester, _check(1));
      expect(
        find.text(
          'O servidor encontrou um problema. Toque em ✓ para tentar de novo.',
        ),
        findsOneWidget,
      );

      await _tap(tester, _check(1));
      expect(server.setBodies, hasLength(2));
      expect(find.textContaining('Toque em ✓'), findsNothing);
    },
  );

  testWidgets('treino livre: acrescentar exercício e exigir repetições', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _tap(tester, find.text('Fichas de treino'));
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Treino livre'));
    expect(find.text('Treino livre'), findsWidgets);

    await _tap(
      tester,
      find.widgetWithText(OutlinedButton, 'Adicionar exercício'),
    );
    await _tap(tester, find.text('Flexão de braços'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Adicionar (1)'));
    expect(find.text('Flexão de braços'), findsOneWidget);

    // Sem plano nem histórico: precisa digitar.
    await _tap(tester, _check(1, 'Flexão de braços'));
    expect(find.textContaining('Informe as repetições.'), findsOneWidget);
    expect(server.setBodies, isEmpty);

    await tester.enterText(find.byType(TextField).last, '20');
    await _tap(tester, _check(1, 'Flexão de braços'));
    expect(server.setBodies.single, {'kind': 'working', 'reps': 20});
    // Sempre sobra uma linha para a próxima série.
    expect(_check(2, 'Flexão de braços'), findsOneWidget);
  });

  testWidgets('corrigir e apagar uma série feita', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _startTemplate(tester);
    await tester.enterText(find.byType(TextField).at(0), '50');
    await _tap(tester, _check(1));

    await _tap(tester, find.bySemanticsLabel(RegExp('Série 1 feita')));
    await tester.enterText(find.widgetWithText(TextField, 'Repetições'), '9');
    await _tap(tester, find.widgetWithText(FilledButton, 'Salvar'));
    expect(server.setBodies.last, {'reps': 9, 'load_kg': 50.0});
    expect(find.bySemanticsLabel(RegExp('50 kg × 9')), findsOneWidget);

    await _tap(tester, find.bySemanticsLabel(RegExp('Série 1 feita')));
    await _tap(tester, find.text('Apagar'));
    expect(find.bySemanticsLabel(RegExp('Série 1 feita')), findsNothing);
    expect(server.sessionCalls.last, 'DELETE exercises');
  });

  testWidgets('pausar e retomar', (tester) async {
    await _pumpSignedIn(tester);
    await _startTemplate(tester);

    await _tap(tester, find.byTooltip('Pausar treino'));
    expect(find.textContaining('Pausado'), findsOneWidget);
    await _tap(tester, find.byTooltip('Retomar treino'));
    expect(find.textContaining('Pausado'), findsNothing);
  });

  testWidgets('finalizar com esforço volta ao início com o resumo', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _startTemplate(tester);
    await tester.enterText(find.byType(TextField).at(1), '10');
    await _tap(tester, _check(1));

    await _tap(tester, find.widgetWithText(FilledButton, 'Finalizar treino'));
    await _tap(tester, find.widgetWithText(EvoChip, '8'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Salvar treino'));

    expect(server.finishedSessions.single['perceived_effort'], 8);
    expect(find.text('Treino salvo: 1 série em 30 min'), findsOneWidget);
    expect(find.text('Olá, Ana!'), findsOneWidget);
    expect(find.text('Treino em andamento'), findsNothing);
  });

  testWidgets('finalizar sem séries mostra o motivo', (tester) async {
    await _pumpSignedIn(tester);
    await _startTemplate(tester);

    await _tap(tester, find.widgetWithText(FilledButton, 'Finalizar treino'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Salvar treino'));
    expect(find.text('Registre pelo menos uma série.'), findsOneWidget);
  });

  testWidgets('descartar pede confirmação e apaga o treino', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _startTemplate(tester);

    await _tap(tester, find.byTooltip('Mais opções'));
    await _tap(tester, find.text('Descartar treino'));
    expect(find.text('Descartar treino?'), findsOneWidget);
    await _tap(tester, find.widgetWithText(FilledButton, 'Descartar'));

    expect(server.session, isNull);
    expect(find.text('Olá, Ana!'), findsOneWidget);
  });

  testWidgets('treino aberto aparece no início e um novo início leva até ele', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) => s.session = s.sessionFrom(_template(s)),
    );
    expect(find.text('Treino em andamento'), findsOneWidget);

    await _startTemplate(tester);
    expect(
      find.text('Você já tem um treino em andamento. Continue por aqui.'),
      findsOneWidget,
    );
    expect(_check(1), findsOneWidget);
    expect(server.sessionCalls.first, 'POST start');
  });
}
