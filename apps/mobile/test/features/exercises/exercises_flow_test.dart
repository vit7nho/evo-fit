import 'package:evofit/features/sessions/data/session_draft.dart';
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

Future<void> _openLibrary(WidgetTester tester) =>
    _tap(tester, find.text('Exercícios'));

Finder _chip(String label) => find.widgetWithText(EvoChip, label);

void main() {
  testWidgets('a biblioteca lista o catálogo em ordem e busca sem acentos', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    await _openLibrary(tester);

    expect(find.text('4 exercícios'), findsOneWidget);
    expect(find.text('Agachamento livre'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'triceps');
    await tester.pumpAndSettle();
    expect(find.text('1 exercício'), findsOneWidget);
    expect(find.text('Tríceps francês'), findsOneWidget);
    expect(find.text('Agachamento livre'), findsNothing);
  });

  testWidgets('filtrar por músculo e limpar quando nada aparece', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    await _openLibrary(tester);

    await _tap(tester, _chip('Peito'));
    expect(find.text('2 exercícios'), findsOneWidget);
    expect(find.text('Flexão de braços'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'remada');
    await tester.pumpAndSettle();
    expect(find.text('Nenhum exercício encontrado'), findsOneWidget);

    await _tap(tester, find.text('Limpar filtros'));
    expect(find.text('4 exercícios'), findsOneWidget);
  });

  testWidgets('"Só o que tenho" usa os equipamentos do perfil', (tester) async {
    await _pumpSignedIn(
      tester,
      setUp: (s) => s.profile['equipment'] = ['dumbbells'],
    );
    await _openLibrary(tester);

    await _tap(tester, _chip('Só o que tenho'));
    // Halteres (do perfil) e peso do corpo (sempre); barra fica de fora.
    expect(find.text('2 exercícios'), findsOneWidget);
    expect(find.text('Tríceps francês'), findsOneWidget);
    expect(find.text('Flexão de braços'), findsOneWidget);
  });

  testWidgets('com academia completa, o filtro de equipamento nem aparece', (
    tester,
  ) async {
    await _pumpSignedIn(tester, setUp: (s) => s.profile['equipment'] = ['gym']);
    await _openLibrary(tester);
    expect(_chip('Só o que tenho'), findsNothing);
  });

  testWidgets('o detalhe mostra músculos e orientação; catálogo é só leitura', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    await _openLibrary(tester);
    await _tap(tester, find.text('Agachamento livre'));
    expect(find.text('Barra e anilhas'), findsOneWidget);

    // As fotos ocupam o topo: o resto do detalhe fica mais abaixo na lista.
    await tester.scrollUntilVisible(
      find.text('Orientação de execução de Agachamento livre.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Músculos principais'), findsOneWidget);
    expect(find.text('Quadríceps'), findsOneWidget);
    expect(find.text('Glúteos'), findsOneWidget);
    expect(
      find.text('Orientação de execução de Agachamento livre.'),
      findsOneWidget,
    );
    expect(find.text('Editar'), findsNothing);
  });

  testWidgets('o detalhe mostra as fotos de início e fim, com crédito', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    await _openLibrary(tester);
    await _tap(tester, find.text('Agachamento livre'));

    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Fim'), findsOneWidget);
    expect(find.textContaining('free-exercise-db'), findsOneWidget);
    expect(find.bySemanticsLabel('Agachamento livre: Início'), findsOneWidget);
    // Nos testes a rede de imagens falha: o espaço mostra um aviso, sem quebrar.
    expect(find.text('Foto indisponível'), findsNWidgets(2));
  });

  testWidgets('exercício sem fotos não mostra o bloco de fotos', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    await _openLibrary(tester);
    await _tap(tester, find.text('Flexão de braços'));

    expect(find.text('Início'), findsNothing);
    expect(find.textContaining('free-exercise-db'), findsNothing);
  });

  testWidgets('cria um exercício próprio e ele aparece em "Meus"', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);
    await _openLibrary(tester);
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Criar exercício'));

    // Sem as escolhas obrigatórias, diz o que falta e não envia.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome'),
      'Remada no TRX',
    );
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar exercício'));
    expect(find.text('Escolha o equipamento.'), findsOneWidget);
    expect(server.exerciseCalls, isEmpty);

    await _tap(tester, _chip('Sem equipamento'));
    await _tap(tester, _chip('Multiarticular'));
    await _tap(tester, _chip('Peso do corpo'));
    await _tap(tester, _chip('Dorsais').first);
    // Escolhido como principal, sai das opções de secundário.
    expect(_chip('Dorsais'), findsOneWidget);
    await _tap(tester, _chip('Tríceps').last);
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar exercício'));

    expect(server.exerciseBodies.single, {
      'name': 'Remada no TRX',
      'instructions': '',
      'equipment': 'bodyweight',
      'mechanics': 'compound',
      'load_type': 'bodyweight',
      'unilateral': false,
      'muscles': [
        {'muscle_group_id': 'lats', 'role': 'primary'},
        {'muscle_group_id': 'triceps', 'role': 'secondary'},
      ],
    });
    expect(find.text('Exercício criado'), findsOneWidget);

    await _tap(tester, _chip('Meus'));
    expect(find.text('1 exercício'), findsOneWidget);
    expect(find.text('Remada no TRX'), findsOneWidget);
    expect(find.text('Seu'), findsOneWidget);
  });

  testWidgets('nome repetido mostra o erro da API no campo', (tester) async {
    await _pumpSignedIn(
      tester,
      setUp: (s) => s.exercises.add({
        'id': 'ex-meu',
        'name': 'Remada no TRX',
        'instructions': null,
        'mechanics': 'compound',
        'equipment': 'bodyweight',
        'load_type': 'bodyweight',
        'unilateral': false,
        'is_custom': true,
        'is_active': true,
        'muscles': [
          {'id': 'lats', 'name': 'Dorsais', 'role': 'primary'},
        ],
      }),
    );
    await _openLibrary(tester);
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Criar exercício'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome'),
      'Remada no TRX',
    );
    await _tap(tester, _chip('Sem equipamento'));
    await _tap(tester, _chip('Multiarticular'));
    await _tap(tester, _chip('Peso do corpo'));
    await _tap(tester, _chip('Dorsais').first);
    await _tap(tester, find.widgetWithText(FilledButton, 'Criar exercício'));

    expect(find.text('Você já tem um exercício com esse nome.'), findsWidgets);
    expect(
      find.widgetWithText(FilledButton, 'Criar exercício'),
      findsOneWidget,
    );
  });

  testWidgets('arquivar e restaurar um exercício próprio', (tester) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) => s.exercises.add({
        'id': 'ex-meu',
        'name': 'Remada no TRX',
        'instructions': null,
        'mechanics': 'compound',
        'equipment': 'bodyweight',
        'load_type': 'bodyweight',
        'unilateral': false,
        'is_custom': true,
        'is_active': true,
        'muscles': [
          {'id': 'lats', 'name': 'Dorsais', 'role': 'primary'},
        ],
      }),
    );
    await _openLibrary(tester);
    await _tap(tester, find.text('Remada no TRX'));
    expect(find.text('Editar'), findsOneWidget);

    await _tap(tester, find.text('Arquivar exercício'));
    expect(server.exerciseBodies.single, {'is_active': false});
    expect(find.text('Arquivado'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    // Fora de "Meus", o arquivado não aparece; em "Meus", fica na seção própria.
    expect(find.text('Remada no TRX'), findsNothing);
    await _tap(tester, _chip('Meus'));
    expect(find.text('Arquivados'), findsOneWidget);

    await _tap(tester, find.text('Remada no TRX'));
    await _tap(tester, find.text('Restaurar exercício'));
    expect(server.exerciseBodies.last, {'is_active': true});
  });
}
