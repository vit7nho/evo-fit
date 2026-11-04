import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/plans/domain/plan.dart';
import 'package:evofit/features/profile/application/profile_actions.dart';
import 'package:evofit/features/plans/presentation/plan_widgets.dart';
import 'package:evofit/features/sessions/data/session_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

Future<FakeAuthServer> _pumpSignedIn(
  WidgetTester tester, {
  List<Map<String, Object?>> activities = const [],
  Set<String> consents = const {},
  void Function(FakeAuthServer server)? setUp,
}) async {
  final server = FakeAuthServer(validRefreshToken: 'salvo')
    ..activities = [...activities];
  server.consents.addAll(consents);
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

Future<void> _openPlans(WidgetTester tester) async {
  final card = find.text('Planos');
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await _tap(tester, card);
}

/// Começa o plano de 5 km (segunda, quarta e sexta, hoje) e abre o plano.
Future<void> _start5k(WidgetTester tester) async {
  await _openPlans(tester);
  await _tap(tester, find.text('Primeiros 5 km'));
  await _tap(tester, find.widgetWithText(FilledButton, 'Começar plano'));
}

/// O progresso fica no topo do plano (a lista pode ter rolado).
Future<void> _expectProgress(WidgetTester tester, String text) async {
  await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
  await tester.pumpAndSettle();
  expect(find.text(text), findsOneWidget);
}

String _today() => DateTime.now().toIso8601String().substring(0, 10);

void main() {
  group('dias do plano', () {
    test('3 dias; na corrida, sem dias seguidos', () {
      expect(checkPlanWeekdays({0, 2, 4}, runs: true), isNull);
      expect(checkPlanWeekdays({0, 2}, runs: true), 'Escolha 3 dias.');
      expect(
        checkPlanWeekdays({0, 1, 3}, runs: true),
        'Na corrida, deixe um dia de descanso entre as sessões.',
      );
      // Domingo e segunda são seguidos.
      expect(checkPlanWeekdays({6, 0, 3}, runs: true), isNotNull);
      expect(checkPlanWeekdays({0, 1, 2}, runs: false), isNull);
    });

    test('duração prevista em minutos', () {
      expect(formatPlannedDuration(1800), '~30 min');
      expect(formatPlannedDuration(1830), '~31 min');
      expect(formatPlannedDuration(4500), '~1 h 15 min');
      expect(formatPlannedDuration(3600), '~1 h');
    });
  });

  testWidgets('começa o plano com os dias escolhidos', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _openPlans(tester);

    expect(find.text('Escolha um plano'), findsOneWidget);
    expect(find.text('Hábito de caminhada'), findsOneWidget);
    // O aviso do 10 km vem da API (sem corrida de 5 km no histórico).
    expect(
      find.text('Para o 10 km, o ideal é já correr 5 km sem parar.'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Primeiros 5 km'));
    expect(find.text('9 semanas · 3 sessões por semana'), findsOneWidget);

    await _tap(tester, find.text('sex'));
    await _tap(tester, find.text('sáb'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Começar plano'));

    expect(server.planBodies.single, {
      'kind': 'run_5k',
      'weekdays': [0, 2, 5],
      'start_date': _today(),
    });
    // Abre o plano novo; voltar leva a Planos (a configuração saiu da pilha).
    await _expectProgress(tester, 'Semana 1 de 9 · 0 de 27 sessões');
    expect(find.text('Próxima sessão'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Em andamento'), findsOneWidget);
    expect(find.text('Escolha um plano'), findsNothing);
    // O resumo da lista não traz as sessões: a semana vem da API.
    expect(find.text('Semana 1 de 9 · 0 de 27 sessões'), findsOneWidget);
  });

  testWidgets('dias seguidos na corrida não deixam começar', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _openPlans(tester);
    await _tap(tester, find.text('Primeiros 5 km'));

    await _tap(tester, find.text('qua'));
    expect(find.text('Escolha 3 dias.'), findsOneWidget);
    await _tap(tester, find.text('ter'));
    expect(
      find.text('Na corrida, deixe um dia de descanso entre as sessões.'),
      findsOneWidget,
    );
    final begin = find.widgetWithText(FilledButton, 'Começar plano');
    expect(tester.widget<FilledButton>(begin).onPressed, isNull);
    expect(server.planCalls, isEmpty);
  });

  testWidgets('registrar a sessão cria a corrida e marca a sessão', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _start5k(tester);

    await _tap(tester, find.widgetWithText(FilledButton, 'Registrar sessão'));
    expect(find.text('Primeiros 5 km · semana 1, sessão 1'), findsOneWidget);
    // Corrida já escolhida (sem as outras modalidades) e a duração prevista.
    expect(find.text('Modalidade'), findsNothing);
    expect(find.text('Corrida'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '30:00'), findsOneWidget);

    await _tap(tester, find.widgetWithText(FilledButton, 'Registrar'));

    expect(server.activityBodies.single['modality'], 'run');
    expect(server.activityBodies.single['duration_s'], 1800);
    expect(server.planBodies.last, {'activity_id': 'atividade-1'});
    expect(find.text('Sessão concluída. Bom trabalho!'), findsOneWidget);
    await _expectProgress(tester, 'Semana 1 de 9 · 1 de 27 sessões');
  });

  testWidgets('se a marcação falhar, a atividade fica e o aviso explica', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _start5k(tester);
    server.rejectPlanLink = 'A atividade é de antes do início do plano.';

    await _tap(tester, find.widgetWithText(FilledButton, 'Registrar sessão'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Registrar'));

    expect(server.activities, hasLength(1));
    expect(
      find.text(
        'Atividade registrada, mas a sessão não foi marcada: '
        'A atividade é de antes do início do plano.',
      ),
      findsOneWidget,
    );
    await _expectProgress(tester, 'Semana 1 de 9 · 0 de 27 sessões');
  });

  testWidgets('usa uma corrida já registrada desde o início do plano', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final server = await _pumpSignedIn(
      tester,
      activities: [
        FakeAuthServer.run(
          id: 'hoje',
          startedAt: now.toIso8601String(),
          durationS: 1500,
          distanceM: 4000,
        ),
        // Antes do início do plano: não aparece.
        FakeAuthServer.run(id: 'antiga', startedAt: '2025-01-10T09:00:00Z'),
        {
          ...FakeAuthServer.run(id: 'pedal', startedAt: now.toIso8601String()),
          'modality': 'cycle',
        },
      ],
    );
    await _start5k(tester);

    await _tap(
      tester,
      find.widgetWithText(OutlinedButton, 'Usar atividade já registrada'),
    );
    expect(find.text('Qual atividade foi esta sessão?'), findsOneWidget);
    expect(find.byType(ListTile).hitTestable(), findsNWidgets(1));
    await _tap(tester, find.text('25:00 · 4 km'));

    expect(server.planBodies.last, {'activity_id': 'hoje'});
    await _expectProgress(tester, 'Semana 1 de 9 · 1 de 27 sessões');
  });

  testWidgets('desmarca a sessão e encerra o plano', (tester) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final server = await _pumpSignedIn(
      tester,
      activities: [FakeAuthServer.run(id: 'hoje', startedAt: now)],
    );
    await _start5k(tester);
    await _tap(
      tester,
      find.widgetWithText(OutlinedButton, 'Usar atividade já registrada'),
    );
    await _tap(tester, find.text('30:00 · 5 km'));

    // A sessão feita abre com "Desmarcar".
    await _tap(tester, find.bySemanticsLabel(RegExp(r'^Sessão 1, feita')));
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Desmarcar sessão'));
    expect(
      server.planCalls.last,
      'DELETE plano-1/sessions/plano-1-sessao-1/activity',
    );
    await _expectProgress(tester, 'Semana 1 de 9 · 0 de 27 sessões');

    await _tap(tester, find.byTooltip('Mais opções'));
    await _tap(tester, find.text('Encerrar plano'));
    await _tap(tester, find.text('Encerrar'));
    expect(find.text('Plano encerrado.'), findsOneWidget);
    expect(find.text('Próxima sessão'), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Escolha um plano'), findsOneWidget);
    final past = find.text('Encerrado · 0 de 27 sessões');
    await tester.scrollUntilVisible(
      past,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Planos anteriores'), findsOneWidget);
    expect(past, findsOneWidget);
  });

  testWidgets('excluir a atividade devolve a sessão para pendente', (
    tester,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _pumpSignedIn(
      tester,
      activities: [FakeAuthServer.run(id: 'hoje', startedAt: now)],
    );
    await _start5k(tester);
    await _tap(
      tester,
      find.widgetWithText(OutlinedButton, 'Usar atividade já registrada'),
    );
    await _tap(tester, find.text('30:00 · 5 km'));
    await _tap(tester, find.bySemanticsLabel(RegExp(r'^Sessão 1, feita')));
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Ver atividade'));

    await _tap(tester, find.byTooltip('Excluir atividade'));
    await _tap(tester, find.text('Excluir'));

    // De volta ao plano, recarregado.
    await _expectProgress(tester, 'Semana 1 de 9 · 0 de 27 sessões');
  });

  testWidgets('revogar os dados de saúde tira o ajuste do plano aberto', (
    tester,
  ) async {
    const adaptation = 'Algumas semanas se repetem.';
    final server = await _pumpSignedIn(
      tester,
      consents: {'health_data'},
      setUp: (server) => server.planTemplates = [
        FakeAuthServer.planTemplate(
          'run_5k',
          'Primeiros 5 km',
          'run',
          weeks: 13,
          adaptations: [adaptation],
        ),
      ],
    );
    await _start5k(tester);
    expect(find.text(adaptation), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(EvoFitApp)),
    );
    final revoke = container
        .read(profileActionsProvider)
        .setConsent('health_data', granted: false);
    await tester.pumpAndSettle();
    await revoke;
    await tester.pumpAndSettle();

    // O servidor tirou o ajuste: a tela aberta é recarregada.
    expect(server.plans.single['adaptations'], isEmpty);
    expect(find.text(adaptation), findsNothing);
    expect(find.text('Semana 1 de 13 · 0 de 39 sessões'), findsOneWidget);
  });
}
