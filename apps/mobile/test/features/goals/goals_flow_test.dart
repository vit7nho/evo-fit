import 'package:evofit/features/sessions/data/session_draft.dart';
import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

/// App inteiro sobre o servidor falso, com uma sessão salva (entra direto no início).
Future<FakeAuthServer> _pumpSignedIn(
  WidgetTester tester, {
  void Function(FakeAuthServer server)? setUp,
}) async {
  final server = FakeAuthServer(validRefreshToken: 'salvo');
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
}

Future<void> _openGoals(WidgetTester tester) =>
    _tap(tester, find.text('Metas'));

void main() {
  testWidgets('sem metas, o início convida e a lista mostra o estado vazio', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    expect(find.text('Defina o que quer alcançar'), findsOneWidget);

    await _openGoals(tester);
    expect(find.text('Nenhuma meta ainda'), findsOneWidget);
    await _tap(tester, find.text('Criar meta'));
    expect(find.text('Que tipo de meta?'), findsOneWidget);
  });

  testWidgets('cria uma meta de força e volta para a lista', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _openGoals(tester);
    await _tap(tester, find.text('Criar meta'));
    await _tap(tester, find.text('Força'));

    await _type(tester, 'Nome da meta', 'Supino de 82,5');
    await _type(tester, 'Exercício', 'Supino reto');
    await _type(tester, 'Carga', '82,5');
    await _type(tester, 'Repetições', '5');
    await _tap(tester, find.text('Alta'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar meta'));

    expect(server.goalBodies.single, {
      'kind': 'strength',
      'title': 'Supino de 82,5',
      'target': {'exercise': 'Supino reto', 'load_kg': 82.5, 'reps': 5},
      'priority': 1,
      'target_date': null,
    });
    // Voltou direto para a lista (a escolha de tipo também saiu).
    expect(find.text('Que tipo de meta?'), findsNothing);
    expect(find.text('Supino de 82,5'), findsOneWidget);
    expect(find.text('Supino reto: 82.5 kg × 5'), findsOneWidget);
    expect(find.text('Meta criada'), findsOneWidget);
  });

  testWidgets('valida no app antes de enviar (passo e faixa)', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _openGoals(tester);
    await _tap(tester, find.text('Criar meta'));
    await _tap(tester, find.text('Força'));

    await _tap(tester, find.widgetWithText(FilledButton, 'Criar meta'));
    expect(find.text('Dê um nome para a meta.'), findsOneWidget);
    expect(find.text('Campo obrigatório.'), findsNWidgets(3));

    await _type(tester, 'Nome da meta', 'Supino');
    await _type(tester, 'Exercício', 'Supino');
    await _type(tester, 'Carga', '80,3');
    await _type(tester, 'Repetições', '50');
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar meta'));

    expect(find.text('Use múltiplos de 0,5.'), findsOneWidget);
    expect(find.text('Informe um valor entre 1 e 30.'), findsOneWidget);
    expect(server.goalCalls, isEmpty);
  });

  testWidgets('tempo de corrida aceita mm:ss e envia segundos', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _openGoals(tester);
    await _tap(tester, find.text('Criar meta'));
    await _tap(tester, find.text('Tempo de corrida'));

    await _type(tester, 'Nome da meta', 'Meus 5 km');
    await _type(tester, 'Distância', '5');
    await _type(tester, 'Tempo', '25:70');
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar meta'));
    expect(find.text('Use o formato mm:ss ou h:mm:ss.'), findsOneWidget);

    await _type(tester, 'Tempo', '25:30');
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar meta'));
    expect(server.goalBodies.single['target'], {
      'distance_km': 5.0,
      'time_s': 1530,
    });
  });

  testWidgets('escolha opcional começa em "Qualquer" e não é enviada', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _openGoals(tester);
    await _tap(tester, find.text('Criar meta'));
    await _tap(tester, find.text('Frequência'));

    await _type(tester, 'Nome da meta', 'Treinar mais');
    await _type(tester, 'Treinos por semana', '3');
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar meta'));
    expect(server.goalBodies.single['target'], {'sessions_per_week': 3});
  });

  testWidgets('meta de peso pede a autorização antes de enviar', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _openGoals(tester);
    await _tap(tester, find.text('Criar meta'));
    expect(find.text('Usa dado de saúde (peso)'), findsOneWidget);
    await _tap(tester, find.text('Perder peso'));

    await _type(tester, 'Nome da meta', 'Chegar a 70');
    await _type(tester, 'Peso desejado', '70');
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar meta'));
    expect(
      find.text('Autorize o uso do seu peso para salvar esta meta.'),
      findsOneWidget,
    );
    expect(server.goalCalls, isEmpty);

    await _tap(tester, find.byType(Switch));
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar meta'));
    // O consentimento vem antes da meta: sem ele a API recusaria.
    expect(server.consentCalls, ['PUT health_data']);
    expect(server.goalCalls, ['POST']);
    expect(find.text('Chegar a 70'), findsOneWidget);
  });

  testWidgets('erro da API aparece no formulário', (tester) async {
    await _pumpSignedIn(tester, setUp: (s) => s.goalLimitReached = true);
    await _openGoals(tester);
    await _tap(tester, find.text('Criar meta'));
    await _tap(tester, find.text('Frequência'));
    await _type(tester, 'Nome da meta', 'Treinar mais');
    await _type(tester, 'Treinos por semana', '3');
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar meta'));

    expect(find.text('Você já tem 30 metas ativas.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Criar meta'), findsOneWidget);
  });

  group('meta existente', () {
    void withGoal(FakeAuthServer s) =>
        s.goals = [FakeAuthServer.strengthGoal()];

    testWidgets('o início conta as ativas e a lista mostra o resumo', (
      tester,
    ) async {
      await _pumpSignedIn(tester, setUp: withGoal);
      expect(find.text('1 meta ativa'), findsOneWidget);

      await _openGoals(tester);
      expect(find.text('Supino de 80 kg'), findsOneWidget);
      expect(find.text('Supino: 80 kg × 5'), findsOneWidget);
      expect(find.text('Força · Prioridade média'), findsOneWidget);
    });

    testWidgets('editar o nome envia a alteração', (tester) async {
      final server = await _pumpSignedIn(tester, setUp: withGoal);
      await _openGoals(tester);
      await _tap(tester, find.text('Supino de 80 kg'));

      await _type(tester, 'Nome da meta', 'Supino pesado');
      await _tap(tester, find.widgetWithText(FilledButton, 'Salvar'));

      expect(server.goalCalls, ['PATCH meta-1']);
      expect(server.goalBodies.single['title'], 'Supino pesado');
      expect(find.text('Supino pesado'), findsOneWidget);
    });

    testWidgets('marcar como alcançada leva para as concluídas', (
      tester,
    ) async {
      final server = await _pumpSignedIn(tester, setUp: withGoal);
      await _openGoals(tester);
      await _tap(tester, find.text('Supino de 80 kg'));

      await _tap(tester, find.text('Marcar como alcançada'));

      expect(server.goalBodies.single['status'], 'achieved');
      expect(find.text('Meta alcançada. Parabéns!'), findsOneWidget);
      expect(find.text('Concluídas'), findsOneWidget);
      expect(find.text('Nenhuma meta ativa'), findsOneWidget);
    });

    testWidgets('excluir pede confirmação', (tester) async {
      final server = await _pumpSignedIn(tester, setUp: withGoal);
      await _openGoals(tester);
      await _tap(tester, find.text('Supino de 80 kg'));

      await _tap(tester, find.text('Excluir meta'));
      expect(find.text('Excluir meta?'), findsOneWidget);
      await _tap(tester, find.text('Cancelar'));
      expect(server.goalCalls, isEmpty);

      await _tap(tester, find.text('Excluir meta'));
      await _tap(tester, find.widgetWithText(FilledButton, 'Excluir'));
      expect(server.goalCalls, ['DELETE meta-1']);
      expect(find.text('Nenhuma meta ainda'), findsOneWidget);
    });

    testWidgets('voltar com alterações não salvas pede confirmação', (
      tester,
    ) async {
      final server = await _pumpSignedIn(tester, setUp: withGoal);
      await _openGoals(tester);
      await _tap(tester, find.text('Supino de 80 kg'));
      await _type(tester, 'Nome da meta', 'Outro nome');
      await tester.pump();

      await _tap(tester, find.byType(BackButton));
      expect(find.text('Descartar alterações?'), findsOneWidget);
      await _tap(tester, find.text('Descartar'));
      expect(find.text('Supino de 80 kg'), findsOneWidget);
      expect(server.goalCalls, isEmpty);
    });

    testWidgets('ao sair e entrar de novo a lista é buscada outra vez', (
      tester,
    ) async {
      final server = await _pumpSignedIn(tester, setUp: withGoal);
      final before = server.goalListCalls;

      await _tap(tester, find.byTooltip('Perfil'));
      final logout = find.widgetWithText(OutlinedButton, 'Sair da conta');
      await tester.scrollUntilVisible(
        logout,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await _tap(tester, logout);
      await _tap(tester, find.widgetWithText(FilledButton, 'Sair'));

      await tester.enterText(_field('E-mail'), FakeAuthServer.email);
      await tester.enterText(_field('Senha'), FakeAuthServer.password);
      await _tap(tester, find.widgetWithText(FilledButton, 'Entrar'));

      // A lista da conta anterior não foi reaproveitada.
      expect(server.goalListCalls, greaterThan(before));
      expect(find.text('1 meta ativa'), findsOneWidget);
    });
  });
}
