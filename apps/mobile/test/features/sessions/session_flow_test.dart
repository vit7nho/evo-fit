import 'package:evofit/features/sessions/data/session_draft.dart';
import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/home/presentation/home_page.dart';
import 'package:evofit/features/sessions/application/session_controller.dart';
import 'package:evofit/shared/widgets/evo_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

const _supino = 'Supino reto com barra';

/// Ficha com um exercício avulso (descanso 90 s) e um bi-set (descanso 60 s após a rodada).
/// [firstKind]: tipo planejado da 1ª série do supino (ex.: `drop` para drop set).
Map<String, Object?> _template(
  FakeAuthServer s, {
  String firstKind = 'working',
}) => s.templateFrom('ficha-a', 1, {
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
          {
            'kind': i == 0 ? firstKind : 'working',
            'reps_min': 8,
            'reps_max': 12,
          },
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
        draftStorageProvider.overrideWithValue(InMemoryDraftStorage()),
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

Finder _check(int set, [String exercise = _supino]) =>
    find.byTooltip('Concluir série $set de $exercise');

/// A barra do descanso ("Descanso 01:30"), não o botão "Descanso: 1 min 30 s".
final _restTimer = find.textContaining(RegExp(r'^Descanso (\d|t)'));

Finder _undo(int set) => find.byTooltip('Desfazer série $set de $_supino');

/// Campos do supino (as linhas vêm primeiro na tela): carga e repetições da linha.
Finder _kg(int row) => find.byType(TextField).at(row * 2);
Finder _reps(int row) => find.byType(TextField).at(row * 2 + 1);

/// Abre o menu do tipo no número da linha e escolhe [option].
Future<void> _setKind(
  WidgetTester tester,
  String rowLabel,
  String option,
) async {
  await _tap(tester, find.bySemanticsLabel(RegExp('^$rowLabel.*mudar o tipo')));
  await _tap(tester, find.widgetWithText(ListTile, option));
}

void main() {
  testWidgets(
    'a coluna anterior e um toque no ✓ com os valores da última vez',
    (tester) async {
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
      expect(find.text('60 kg × 10'), findsOneWidget);
      expect(find.text('62,5 kg × 8'), findsOneWidget);
      await _tap(tester, _check(1));

      expect(server.setBodies.single, {
        'kind': 'working',
        'reps': 10,
        'load_kg': 60.0,
      });
      expect(_undo(1), findsOneWidget);
      // Descanso do exercício avulso.
      expect(find.text('Descanso 01:30'), findsOneWidget);

      await _tap(tester, _check(2));
      expect(server.setBodies.last, {
        'kind': 'working',
        'reps': 8,
        'load_kg': 62.5,
      });
    },
  );

  testWidgets('o digitado vale mais que a sugestão; aquecimento pelo menu', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _startTemplate(tester);

    await _setKind(tester, 'Série 1 de $_supino, válida', 'Aquecimento');
    await tester.enterText(_kg(0), '20');
    await tester.enterText(_reps(0), '15');
    await _tap(
      tester,
      find.byTooltip('Concluir série de aquecimento de $_supino'),
    );

    expect(server.setBodies.single, {
      'kind': 'warmup',
      'reps': 15,
      'load_kg': 20.0,
    });
    // O aquecimento não conta: a linha seguinte é a série 1.
    expect(_check(1), findsOneWidget);
  });

  testWidgets('dá para concluir fora de ordem sem as linhas mudarem', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _startTemplate(tester);
    await tester.enterText(_kg(1), '70');

    await _tap(tester, _check(2));
    expect(server.setBodies.single, {
      'kind': 'working',
      'reps': 8,
      'load_kg': 70.0,
    });
    expect(_check(1), findsOneWidget);
    expect(_undo(2), findsOneWidget);

    await tester.enterText(_kg(0), '60');
    await _tap(tester, _check(1));
    expect(_undo(1), findsOneWidget);
    expect(_undo(2), findsOneWidget);
  });

  testWidgets('no bi-set, o descanso só começa no fim da rodada', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    await _startTemplate(tester);
    expect(find.text('Bi-set · descanso 1 min após a rodada'), findsOneWidget);

    // Tríceps (1º do bi-set): sem descanso.
    await _tap(tester, _check(1, 'Tríceps francês'));
    expect(_restTimer, findsNothing);

    // Agachamento (último do bi-set): descanso do grupo.
    await _tap(tester, _check(1, 'Agachamento livre'));
    expect(find.text('Descanso 01:00'), findsOneWidget);

    await _tap(tester, find.bySemanticsLabel('Mais 15 segundos'));
    expect(find.text('Descanso 01:15'), findsOneWidget);
    await _tap(tester, find.text('Pular'));
    expect(_restTimer, findsNothing);
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

    // Peso do corpo: só o campo de repetições.
    await tester.enterText(find.byType(TextField).last, '20');
    await _tap(tester, _check(1, 'Flexão de braços'));
    expect(server.setBodies.single, {'kind': 'working', 'reps': 20});

    await _tap(tester, find.widgetWithText(OutlinedButton, 'Adicionar série'));
    expect(_check(2, 'Flexão de braços'), findsOneWidget);
  });

  testWidgets('corrigir uma série feita no próprio campo e desfazer', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _startTemplate(tester);
    await tester.enterText(_kg(0), '50');
    await _tap(tester, _check(1));

    await tester.enterText(_reps(0), '9');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(server.setBodies.last, {'reps': 9});

    await _tap(tester, _undo(1));
    expect(server.sessionCalls.last, 'DELETE exercises');
    expect(_check(1), findsOneWidget);
    // Os valores ficam na linha para concluir de novo.
    expect(tester.widget<TextField>(_kg(0)).controller!.text, '50');
  });

  testWidgets('remover uma linha pelo menu do tipo', (tester) async {
    await _pumpSignedIn(tester);
    await _startTemplate(tester);
    expect(_check(3), findsOneWidget);

    await _setKind(tester, 'Série 3 de $_supino', 'Remover série');
    expect(_check(3), findsNothing);
    expect(_check(2), findsOneWidget);
  });

  group('técnicas', () {
    testWidgets('drop: vira D pelo menu, tira 20% e continua a série acima', (
      tester,
    ) async {
      final server = await _pumpSignedIn(tester);
      await _startTemplate(tester);
      await tester.enterText(_kg(0), '60');
      await tester.enterText(_reps(0), '10');
      await _tap(tester, _check(1));

      await _setKind(tester, 'Série 2 de $_supino', 'Drop set');
      // A linha seguinte passa a ser a série 2.
      expect(_check(2), findsOneWidget);
      await tester.enterText(_reps(1), '6');
      await _tap(
        tester,
        find.byTooltip('Concluir drop set da série 1 de $_supino'),
      );

      expect(server.setBodies.last, {
        'kind': 'drop',
        'reps': 6,
        'load_kg': 47.5,
        'parent_set_id': 'serie-1',
      });
      expect(find.text('Descanso 01:30'), findsOneWidget);
    });

    testWidgets('drop planejado na ficha emenda sem descanso', (tester) async {
      final server = await _pumpSignedIn(
        tester,
        setUp: (s) => s.templates = [_template(s, firstKind: 'drop')],
      );
      await _startTemplate(tester);
      await tester.enterText(_kg(0), '60');
      await tester.enterText(_reps(0), '10');
      await _tap(tester, _check(1));

      // A série principal vai como válida; o drop está logo abaixo, sem descanso.
      expect(server.setBodies.single['kind'], 'working');
      expect(_restTimer, findsNothing);
      expect(
        find.byTooltip('Concluir drop set da série 1 de $_supino'),
        findsOneWidget,
      );
    });

    testWidgets('rest-pause planejado: pausa curta e mesma carga', (
      tester,
    ) async {
      final server = await _pumpSignedIn(
        tester,
        setUp: (s) => s.templates = [_template(s, firstKind: 'rest_pause')],
      );
      await _startTemplate(tester);
      await tester.enterText(_kg(0), '60');
      await tester.enterText(_reps(0), '8');
      await _tap(tester, _check(1));
      expect(find.text('Descanso 00:15'), findsOneWidget);

      await tester.enterText(_reps(1), '3');
      await _tap(
        tester,
        find.byTooltip('Concluir rest-pause da série 1 de $_supino'),
      );
      expect(server.setBodies.last, {
        'kind': 'rest_pause',
        'reps': 3,
        'load_kg': 60.0,
        'parent_set_id': 'serie-1',
      });
    });

    testWidgets('até a falha pelo menu, antes e depois de concluir', (
      tester,
    ) async {
      final server = await _pumpSignedIn(tester);
      await _startTemplate(tester);
      await _setKind(tester, 'Série 1 de $_supino', 'Até a falha');
      expect(find.text('F'), findsOneWidget);
      await tester.enterText(_kg(0), '60');
      await _tap(tester, _check(1));
      expect(server.setBodies.single, {
        'kind': 'working',
        'to_failure': true,
        'reps': 8,
        'load_kg': 60.0,
      });

      await _setKind(tester, 'Série 1 de $_supino, até a falha', 'Válida');
      expect(server.setBodies.last, {'kind': 'working', 'to_failure': false});
      expect(find.text('F'), findsNothing);
    });

    testWidgets('a primeira linha não vira drop: falta uma série acima', (
      tester,
    ) async {
      await _pumpSignedIn(tester);
      await _startTemplate(tester);
      await _tap(
        tester,
        find.bySemanticsLabel(RegExp('^Série 1 de $_supino.*mudar o tipo')),
      );
      final drop = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Drop set'),
      );
      expect(drop.enabled, isFalse);
      expect(find.text('Precisa de uma série válida acima.'), findsWidgets);
    });

    testWidgets('a última vez traz o drop na linha dele', (tester) async {
      await _pumpSignedIn(
        tester,
        setUp: (s) => s.previousSets = {
          'ex-supino': [
            {
              'kind': 'working',
              'reps': 10,
              'load_kg': 60,
              'duration_s': null,
              'to_failure': true,
              'segments': [
                {'kind': 'drop', 'reps': 6, 'load_kg': 45, 'duration_s': null},
              ],
            },
          ],
        },
      );
      await _startTemplate(tester);
      expect(find.text('60 kg × 10 (F)'), findsOneWidget);
      expect(find.text('45 kg × 6'), findsOneWidget);
    });
  });

  testWidgets('descanso e nota do exercício mudam no próprio treino', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _startTemplate(tester);

    await _tap(tester, find.widgetWithText(ActionChip, 'Descanso: 1 min 30 s'));
    await _tap(tester, find.widgetWithText(ListTile, '2 min'));
    expect(server.exerciseUpdates.last, {'rest_s': 120});
    expect(find.widgetWithText(ActionChip, 'Descanso: 2 min'), findsOneWidget);

    await _tap(tester, find.widgetWithText(ActionChip, 'Nota').first);
    await tester.enterText(find.byType(TextField).last, 'Banco no 3');
    await _tap(tester, find.widgetWithText(FilledButton, 'Salvar'));
    expect(server.exerciseUpdates.last, {'notes': 'Banco no 3'});
    expect(find.text('Banco no 3'), findsOneWidget);

    // O descanso novo vale para a próxima série.
    await _tap(tester, _check(1));
    expect(find.text('Descanso 02:00'), findsOneWidget);
  });

  testWidgets('o resumo do topo soma volume e séries na hora', (tester) async {
    await _pumpSignedIn(tester);
    await _startTemplate(tester);
    expect(find.bySemanticsLabel('Séries: 0'), findsOneWidget);

    await tester.enterText(_kg(0), '60');
    await tester.enterText(_reps(0), '10');
    await _tap(tester, _check(1));
    expect(find.bySemanticsLabel('Volume: 600 kg'), findsOneWidget);
    expect(find.bySemanticsLabel('Séries: 1'), findsOneWidget);
  });

  testWidgets('pausar e retomar', (tester) async {
    await _pumpSignedIn(tester);
    await _startTemplate(tester);

    await _tap(tester, find.byTooltip('Pausar treino'));
    expect(find.textContaining('Pausado'), findsOneWidget);
    await _tap(tester, find.byTooltip('Retomar treino'));
    expect(find.textContaining('Pausado'), findsNothing);
  });

  testWidgets('finalizar abre o resumo do treino com os recordes', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) => s.finishRecords = [
        {
          'exercise_id': 'ex-supino',
          'kind': 'max_load',
          'value': 60,
          'reps': 10,
          'load_kg': 60,
          'previous': 57.5,
        },
      ],
    );
    await _startTemplate(tester);
    await tester.enterText(_reps(0), '10');
    await _tap(tester, _check(1));

    await _tap(tester, find.widgetWithText(FilledButton, 'Finalizar treino'));
    await _tap(tester, find.widgetWithText(EvoChip, '8'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Salvar treino'));

    expect(server.finishedSessions.single['perceived_effort'], 8);
    expect(
      find.text('Treino salvo: 1 série em 30 min · 1 recorde'),
      findsOneWidget,
    );
    expect(find.text('1 recorde neste treino'), findsOneWidget);
    expect(find.bySemanticsLabel('Esforço: 8/10'), findsOneWidget);

    // Voltar leva ao Início, sem treino aberto.
    await _tap(tester, find.byTooltip('Voltar'));
    expect(find.byType(HomePage), findsOneWidget);
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
    expect(find.byType(HomePage), findsOneWidget);
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
