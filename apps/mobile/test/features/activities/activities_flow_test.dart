import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/activities/application/activities_controller.dart';
import 'package:evofit/features/activities/domain/activity.dart';
import 'package:evofit/features/goals/application/goals_controller.dart';
import 'package:evofit/features/profile/application/profile_actions.dart';
import 'package:evofit/features/activities/presentation/activity_form_page.dart';
import 'package:evofit/features/sessions/data/session_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

/// App inteiro sobre o servidor falso, com uma sessão salva (entra direto no início).
Future<FakeAuthServer> _pumpSignedIn(
  WidgetTester tester, {
  List<Map<String, Object?>> activities = const [],
  Set<String> consents = const {},
}) async {
  final server = FakeAuthServer(validRefreshToken: 'salvo')
    ..activities = [...activities];
  server.consents.addAll(consents);
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

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), text);
  await tester.pumpAndSettle();
}

Future<void> _openNew(WidgetTester tester) async {
  await _tap(tester, find.text('Atividades'));
  await _tap(tester, find.widgetWithText(FilledButton, 'Registrar atividade'));
}

Future<void> _register(WidgetTester tester) =>
    _tap(tester, find.widgetWithText(FilledButton, 'Registrar'));

void main() {
  group('duração digitada', () {
    test('minutos, mm:ss e h:mm:ss', () {
      expect(parseActivityDuration('45'), 45 * 60);
      expect(parseActivityDuration('25:30'), 25 * 60 + 30);
      expect(parseActivityDuration('1:05:00'), 3900);
      expect(parseActivityDuration('1:75'), isNull);
      expect(parseActivityDuration('abc'), isNull);
    });
  });

  group('ritmo', () {
    test('pace por km, km/h no ciclismo e por 100 m na natação', () {
      // Aceite da Fase 3: 5 km em 30 min = 6:00/km.
      expect(liveRhythm('run', 5000, 1800), '6:00 /km');
      expect(liveRhythm('walk', 4000, 2700), '11:15 /km');
      expect(liveRhythm('cycle', 30000, 3600), '30 km/h');
      expect(liveRhythm('cycle', 25500, 3600), '25,5 km/h');
      expect(liveRhythm('swim', 1000, 1200), '2:00 /100 m');
      expect(liveRhythm('run', null, 1800), isNull);
      expect(liveRhythm('run', 5000, null), isNull);
    });
  });

  testWidgets('sem atividades, a lista explica e leva ao registro', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    expect(find.text('Corrida, caminhada, ciclismo e natação'), findsOneWidget);

    await _tap(tester, find.text('Atividades'));
    expect(find.text('Nenhuma atividade ainda'), findsOneWidget);
    await _tap(
      tester,
      find.widgetWithText(FilledButton, 'Registrar atividade'),
    );
    expect(find.text('Modalidade'), findsOneWidget);
  });

  testWidgets('registra uma corrida e ela aparece na lista', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _openNew(tester);

    await _type(tester, 'Duração', '30');
    await _type(tester, 'Distância (opcional)', '5,2');
    await _tap(tester, find.text('7'));
    await _register(tester);

    final body = server.activityBodies.single;
    expect(body['modality'], 'run');
    expect(body['duration_s'], 1800);
    expect(body['distance_m'], 5200);
    expect(body['perceived_effort'], 7);
    expect(body['notes'], isNull);
    expect(body.containsKey('indoor'), isFalse);
    expect(body.containsKey('laps'), isFalse);
    // Data com fuso (a API recusa sem).
    expect(DateTime.parse(body['started_at']! as String).isUtc, isTrue);

    expect(find.text('Atividade registrada'), findsOneWidget);
    expect(find.text('Corrida'), findsOneWidget);
    expect(
      find.text('30:00 · 5,2 km · 5:46 /km · esforço 7/10'),
      findsOneWidget,
    );
  });

  testWidgets('natação na piscina: a distância sai das voltas', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _openNew(tester);

    await _tap(tester, find.text('Natação'));
    await _type(tester, 'Duração', '40:00');
    // Águas abertas: distância em metros.
    expect(_field('Distância (opcional)'), findsOneWidget);
    await _tap(tester, find.text('25 m'));
    expect(_field('Distância (opcional)'), findsNothing);
    await _type(tester, 'Voltas', '40');
    expect(find.text('Distância: 1000 m'), findsOneWidget);
    await _tap(tester, find.text('Crawl'));
    await _register(tester);

    final body = server.activityBodies.single;
    expect(body['modality'], 'swim');
    expect(
      [body['pool_length_m'], body['laps'], body['stroke'], body['distance_m']],
      [25, 40, 'freestyle', null],
    );
    expect(find.text('Natação'), findsOneWidget);
    expect(find.textContaining('1000 m'), findsOneWidget);
  });

  testWidgets('ciclismo em ambiente fechado', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _openNew(tester);

    await _tap(tester, find.text('Ciclismo'));
    await _type(tester, 'Duração', '1:00:00');
    await _tap(tester, find.text('Em ambiente fechado'));
    await _register(tester);

    expect(server.activityBodies.single['indoor'], isTrue);
    expect(server.activityBodies.single['duration_s'], 3600);
  });

  testWidgets('valida antes de enviar e mostra o erro do servidor no campo', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _openNew(tester);

    await _register(tester);
    expect(find.text('Informe a duração.'), findsOneWidget);
    await _type(tester, 'Duração', '0:30');
    await _register(tester);
    expect(find.text('Pelo menos 1 minuto.'), findsOneWidget);
    await _type(tester, 'Distância (opcional)', '400');
    await _register(tester);
    expect(find.text('Acima do limite (300 km).'), findsOneWidget);
    expect(server.activityBodies, isEmpty);

    await _type(tester, 'Duração', '30');
    await _type(tester, 'Distância (opcional)', '5');
    server.rejectActivityField = 'started_at';
    await _register(tester);
    expect(find.text('Recusado pelo servidor.'), findsOneWidget);
    expect(find.text('Registrar atividade'), findsOneWidget);
  });

  testWidgets('corrige e exclui uma atividade', (tester) async {
    final server = await _pumpSignedIn(
      tester,
      activities: [FakeAuthServer.run()],
    );
    await _tap(tester, find.text('Atividades'));
    expect(find.text('30:00 · 5 km · 6:00 /km · esforço 6/10'), findsOneWidget);

    await _tap(tester, find.text('Corrida'));
    expect(find.text('Editar atividade'), findsOneWidget);
    // Modalidade não muda na edição.
    expect(find.text('Modalidade'), findsNothing);
    await _type(tester, 'Duração', '32:10');
    await _tap(tester, find.widgetWithText(FilledButton, 'Salvar'));

    expect(server.activityCalls.last, 'PATCH corrida-1');
    expect(server.activityBodies.last['duration_s'], 32 * 60 + 10);
    expect(server.activityBodies.last.containsKey('modality'), isFalse);
    expect(find.text('32:10 · 5 km · 6:26 /km · esforço 6/10'), findsOneWidget);

    await _tap(tester, find.text('Corrida'));
    await _tap(tester, find.byTooltip('Excluir atividade'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Excluir'));
    expect(server.activityCalls.last, 'DELETE corrida-1');
    expect(find.text('Nenhuma atividade ainda'), findsOneWidget);
  });

  testWidgets('sair com alterações pede confirmação', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _openNew(tester);
    await _type(tester, 'Duração', '30');

    await _tap(tester, find.byTooltip('Voltar'));
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await _tap(tester, find.text('Descartar'));
    expect(find.text('Nenhuma atividade ainda'), findsOneWidget);
    expect(server.activityBodies, isEmpty);
  });

  testWidgets('a lista carrega mais páginas', (tester) async {
    final server = await _pumpSignedIn(
      tester,
      activities: [
        for (var day = 1; day <= 20; day++)
          FakeAuthServer.run(
            id: 'corrida-$day',
            startedAt: '2026-10-${day.toString().padLeft(2, '0')}T09:00:00Z',
          ),
      ],
    );
    await _tap(tester, find.text('Atividades'));

    // Fim da lista, que é montada sob demanda.
    await tester.scrollUntilVisible(
      find.text('Carregar mais'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Carregar mais'), findsOneWidget);
    server.activities = [];
    await _tap(tester, find.text('Carregar mais'));
    expect(find.text('Carregar mais'), findsNothing);
  });

  testWidgets('o pace aparece enquanto se digita', (tester) async {
    await _pumpSignedIn(tester);
    await _openNew(tester);

    await _type(tester, 'Duração', '30');
    expect(find.textContaining('Pace:'), findsNothing);
    await _type(tester, 'Distância (opcional)', '5');
    expect(find.text('Pace: 6:00 /km'), findsOneWidget);

    await _tap(tester, find.text('Ciclismo'));
    await _type(tester, 'Distância (opcional)', '15');
    expect(find.text('Velocidade média: 30 km/h'), findsOneWidget);
  });

  testWidgets('elevação e FC em mais detalhes; FC pede o consentimento', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _openNew(tester);
    await _type(tester, 'Duração', '30');
    await _type(tester, 'Distância (opcional)', '5');

    await _tap(tester, find.text('Mais detalhes'));
    await _type(tester, 'Ganho de elevação (opcional)', '120');
    await _type(tester, 'FC média (opcional)', '150');
    await _type(tester, 'FC máxima (opcional)', '140');
    await _register(tester);
    expect(find.text('Não pode ser menor que a média.'), findsOneWidget);

    await _type(tester, 'FC máxima (opcional)', '178');
    await _register(tester);
    expect(
      find.text('Autorize os dados de saúde para salvar a FC.'),
      findsOneWidget,
    );
    expect(server.activityBodies, isEmpty);

    await _tap(tester, find.text('Autorizo o uso dos meus dados de saúde'));
    await _register(tester);
    expect(server.consents, contains('health_data'));
    final body = server.activityBodies.single;
    expect(
      [body['elevation_gain_m'], body['avg_hr'], body['max_hr']],
      [120, 150, 178],
    );
    expect(find.text('Atividade registrada'), findsOneWidget);
  });

  testWidgets('com o consentimento, a FC vai sem perguntar', (tester) async {
    final server = await _pumpSignedIn(tester, consents: {'health_data'});
    await _openNew(tester);
    await _type(tester, 'Duração', '30');
    await _tap(tester, find.text('Mais detalhes'));
    await _type(tester, 'FC média (opcional)', '140');

    expect(find.text('Autorizo o uso dos meus dados de saúde'), findsNothing);
    await _register(tester);
    expect(server.activityBodies.single['avg_hr'], 140);
  });

  testWidgets('natação não tem elevação', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _openNew(tester);
    await _tap(tester, find.text('Natação'));
    await _type(tester, 'Duração', '30');
    await _tap(tester, find.text('Mais detalhes'));

    expect(find.text('Ganho de elevação (opcional)'), findsNothing);
    await _register(tester);
    expect(
      server.activityBodies.single.containsKey('elevation_gain_m'),
      isFalse,
    );
  });

  testWidgets('revogar os dados de saúde recarrega atividades e metas', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester, consents: {'health_data'});
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EvoFitApp)),
    );
    // Carrega as duas listas (fica alguém ouvindo, como a tela faria).
    container
      ..listen(activitiesProvider, (_, _) {})
      ..listen(goalsProvider, (_, _) {});
    await tester.pumpAndSettle();
    final activityLists = server.activityListCalls;
    final goalLists = server.goalListCalls;

    final revoke = container
        .read(profileActionsProvider)
        .setConsent('health_data', granted: false);
    await tester.pumpAndSettle();
    await revoke;
    await tester.pumpAndSettle();

    // O servidor apagou a FC e as metas de peso: a cópia em memória é refeita.
    expect(server.activityListCalls, activityLists + 1);
    expect(server.goalListCalls, goalLists + 1);
  });
}
