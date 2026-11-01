import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/shared/widgets/evo_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

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

Future<void> _openTemplates(WidgetTester tester) =>
    _tap(tester, find.text('Fichas de treino'));

/// Abre o menu de ações do exercício e escolhe uma.
Future<void> _action(
  WidgetTester tester,
  String exercise,
  String action,
) async {
  await _tap(tester, find.byTooltip('Ações de $exercise'));
  await _tap(tester, find.text(action));
}

Future<void> _pick(WidgetTester tester, List<String> names) async {
  await _tap(
    tester,
    find.widgetWithText(OutlinedButton, 'Adicionar exercícios'),
  );
  for (final name in names) {
    await _tap(tester, find.text(name));
  }
  await _tap(
    tester,
    find.widgetWithText(FilledButton, 'Adicionar (${names.length})'),
  );
}

Map<String, Object?> _existing(FakeAuthServer s) =>
    s.templateFrom('ficha-a', 1, {
      'name': 'Treino A',
      'notes': null,
      'groups': <Object>[],
      'items': [
        {
          'exercise_id': 'ex-supino',
          'planned_sets': [
            {'kind': 'working', 'reps_min': 8, 'reps_max': 12},
            {'kind': 'working', 'reps_min': 8, 'reps_max': 12},
          ],
          'rest_s': 90,
          'notes': null,
          'group': null,
        },
      ],
    });

void main() {
  testWidgets('sem fichas, a lista mostra o estado vazio', (tester) async {
    await _pumpSignedIn(tester);
    expect(find.text('Monte seu primeiro treino'), findsOneWidget);

    await _openTemplates(tester);
    expect(find.text('Nenhuma ficha ainda'), findsOneWidget);
  });

  testWidgets('cria uma ficha com bi-set e envia a estrutura inteira', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _openTemplates(tester);
    await _tap(tester, find.text('Criar ficha'));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome da ficha'),
      'Treino A',
    );
    await _pick(tester, [
      'Supino reto com barra',
      'Tríceps francês',
      'Agachamento livre',
    ]);
    expect(find.text('Exercícios (3)'), findsOneWidget);
    expect(find.text('3 × 8–12 · descanso 1 min 30 s'), findsNWidgets(3));

    await _action(tester, 'Supino reto com barra', 'Juntar com o próximo');
    expect(find.text('Bi-set'), findsOneWidget);
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar ficha'));

    final body = server.templateBodies.single;
    expect(body['name'], 'Treino A');
    expect(body['groups'], [
      {'kind': 'biset', 'rest_after_s': null},
    ]);
    final items = body['items']! as List;
    expect(
      [for (final i in items) (i as Map)['exercise_id']],
      ['ex-supino', 'ex-triceps', 'ex-agachamento'],
    );
    expect([for (final i in items) (i as Map)['group']], [0, 0, null]);
    expect(find.text('Ficha criada'), findsOneWidget);
    expect(find.text('Treino A'), findsOneWidget);
    expect(find.text('3 exercícios · 9 séries'), findsOneWidget);
  });

  testWidgets('o seletor sem escolha avisa o que falta', (tester) async {
    await _pumpSignedIn(tester);
    await _openTemplates(tester);
    await _tap(tester, find.text('Criar ficha'));
    await _tap(
      tester,
      find.widgetWithText(OutlinedButton, 'Adicionar exercícios'),
    );

    await _tap(tester, find.widgetWithText(FilledButton, 'Adicionar'));
    expect(find.text('Marque pelo menos um exercício.'), findsOneWidget);
  });

  testWidgets('ajustar séries, aquecimento e descanso de um exercício', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) => s.templates = [_existing(s)],
    );
    await _openTemplates(tester);
    await _tap(tester, find.text('Treino A'));
    await _tap(tester, find.text('Supino reto com barra'));

    // Série 1 vira aquecimento de 15; mínimo maior que o máximo é recusado.
    await _tap(tester, find.widgetWithText(EvoChip, 'Aquecimento').first);
    final mins = find.widgetWithText(TextFormField, 'Reps mín.');
    final maxs = find.widgetWithText(TextFormField, 'Reps máx.');
    await tester.enterText(mins.first, '15');
    await tester.enterText(maxs.first, '12');
    await _tap(tester, find.widgetWithText(FilledButton, 'Aplicar'));
    expect(find.text('Menor que o mínimo.'), findsOneWidget);

    await tester.enterText(maxs.first, '15');
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Adicionar série'));
    await _tap(tester, find.widgetWithText(EvoChip, '2 min'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Aplicar'));

    expect(find.text('1 aquec. + 2 × 8–12 · descanso 2 min'), findsOneWidget);
    await _tap(tester, find.widgetWithText(FilledButton, 'Salvar'));

    final item = (server.templateBodies.single['items']! as List).single as Map;
    expect(item['planned_sets'], [
      {'kind': 'warmup', 'reps_min': 15, 'reps_max': 15},
      {'kind': 'working', 'reps_min': 8, 'reps_max': 12},
      {'kind': 'working', 'reps_min': 8, 'reps_max': 12},
    ]);
    expect(item['rest_s'], 120);
    expect(server.templateCalls, ['PUT ficha-a']);
  });

  testWidgets('o grupo vira supersérie com descanso após a rodada', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _openTemplates(tester);
    await _tap(tester, find.text('Criar ficha'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome da ficha'),
      'Treino B',
    );
    await _pick(tester, ['Supino reto com barra', 'Tríceps francês']);
    await _action(tester, 'Supino reto com barra', 'Juntar com o próximo');

    await _tap(tester, find.bySemanticsLabel('Ajustar Bi-set'));
    await _tap(tester, find.widgetWithText(EvoChip, 'Supersérie'));
    await _tap(tester, find.widgetWithText(EvoChip, '1 min').last);
    await tester.tapAt(const Offset(20, 40)); // fecha a folha
    await tester.pumpAndSettle();

    expect(
      find.text('Supersérie · descanso 1 min após a rodada'),
      findsOneWidget,
    );
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar ficha'));
    expect(server.templateBodies.single['groups'], [
      {'kind': 'superset', 'rest_after_s': 60},
    ]);
  });

  testWidgets('mover e remover exercícios', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _openTemplates(tester);
    await _tap(tester, find.text('Criar ficha'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome da ficha'),
      'Treino C',
    );
    await _pick(tester, [
      'Supino reto com barra',
      'Tríceps francês',
      'Agachamento livre',
    ]);

    await _action(tester, 'Agachamento livre', 'Mover para cima');
    await _action(tester, 'Tríceps francês', 'Remover');
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar ficha'));

    final items = server.templateBodies.single['items']! as List;
    expect(
      [for (final i in items) (i as Map)['exercise_id']],
      ['ex-supino', 'ex-agachamento'],
    );
  });

  testWidgets('excluir a ficha pede confirmação', (tester) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) => s.templates = [_existing(s)],
    );
    await _openTemplates(tester);
    await _tap(tester, find.text('Treino A'));

    await _tap(tester, find.text('Excluir ficha'));
    expect(find.text('Excluir ficha?'), findsOneWidget);
    await _tap(tester, find.widgetWithText(FilledButton, 'Excluir'));

    expect(server.templateCalls, ['DELETE ficha-a']);
    expect(find.text('Nenhuma ficha ainda'), findsOneWidget);
  });

  testWidgets('voltar com alterações não salvas pede confirmação', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) => s.templates = [_existing(s)],
    );
    await _openTemplates(tester);
    await _tap(tester, find.text('Treino A'));
    await _action(tester, 'Supino reto com barra', 'Remover');

    await _tap(tester, find.byType(BackButton));
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await _tap(tester, find.text('Descartar'));
    expect(find.text('Treino A'), findsOneWidget);
    expect(server.templateCalls, isEmpty);
  });

  testWidgets('sem nome, a ficha não é enviada', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _openTemplates(tester);
    await _tap(tester, find.text('Criar ficha'));

    await _tap(tester, find.widgetWithText(FilledButton, 'Criar ficha'));
    expect(find.text('Dê um nome à ficha.'), findsOneWidget);
    expect(server.templateCalls, isEmpty);
  });
}
