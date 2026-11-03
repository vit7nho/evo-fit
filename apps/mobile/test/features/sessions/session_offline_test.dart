import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/sessions/application/session_controller.dart';
import 'package:evofit/features/sessions/data/session_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

const _supino = 'Supino reto com barra';

Map<String, Object?> _template(FakeAuthServer s) =>
    s.templateFrom('ficha-a', 1, {
      'name': 'Treino A',
      'notes': null,
      'groups': <Object>[],
      'items': [
        {
          'exercise_id': 'ex-supino',
          'planned_sets': [
            for (var i = 0; i < 3; i++)
              {'kind': 'working', 'reps_min': 8, 'reps_max': 12, 'load_kg': 60},
          ],
          'rest_s': 90,
          'notes': null,
          'group': null,
        },
      ],
    });

/// O "aparelho": o servidor falso e os armazenamentos que sobrevivem a fechar o app.
class _Device {
  _Device() {
    server.templates = [_template(server)];
  }

  final server = FakeAuthServer(validRefreshToken: 'salvo');
  final tokens = InMemoryTokenStorage('salvo');
  final drafts = InMemoryDraftStorage();

  /// Abre (ou reabre) o app.
  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        // Uma árvore nova = app reaberto (o estado em memória some).
        key: UniqueKey(),
        retry: noAutomaticRetry,
        overrides: [
          httpClientAdapterProvider.overrideWithValue(server.adapter),
          draftStorageProvider.overrideWithValue(drafts),
          tokenStorageProvider.overrideWithValue(tokens),
          clockTickProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const EvoFitApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Fecha o app.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }
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

Finder _check(int set) => find.byTooltip('Concluir série $set de $_supino');
Finder _pending(int set) =>
    find.byTooltip('Desfazer série $set de $_supino, guardada no aparelho');
Finder _done(int set) => find.byTooltip('Desfazer série $set de $_supino');
Finder _reps(int row) => find.byType(TextField).at(row * 2 + 1);

void main() {
  testWidgets(
    'sem conexão, a série fica no aparelho e vai quando a rede volta',
    (tester) async {
      final device = _Device();
      await device.launch(tester);
      await _startTemplate(tester);

      device.server.offline = true;
      await _tap(tester, _check(1));
      expect(_pending(1), findsOneWidget);
      expect(
        find.text(
          'Sem conexão · 1 alteração guardada no aparelho. Enviamos quando a internet voltar.',
        ),
        findsOneWidget,
      );
      // O descanso segue normal, mesmo sem rede.
      expect(find.text('Descanso 01:30'), findsOneWidget);
      expect(device.drafts.drafts, isNotEmpty);

      device.server.offline = false;
      await _tap(tester, find.widgetWithText(TextButton, 'Tentar agora'));
      expect(device.server.setBodies.single, {
        'kind': 'working',
        'reps': 8,
        'load_kg': 60.0,
      });
      expect(_done(1), findsOneWidget);
      expect(find.textContaining('guardada no aparelho'), findsNothing);
    },
  );

  testWidgets(
    'fechar e reabrir: a fila sobrevive e é enviada sozinha, em ordem',
    (tester) async {
      final device = _Device();
      await device.launch(tester);
      await _startTemplate(tester);

      device.server.offline = true;
      await _tap(tester, _check(1));
      // Drop continuando a série que ainda não foi enviada.
      await _tap(
        tester,
        find.bySemanticsLabel(RegExp('^Série 2 de $_supino.*mudar o tipo')),
      );
      await _tap(tester, find.widgetWithText(ListTile, 'Drop set'));
      await tester.enterText(_reps(1), '6');
      await _tap(
        tester,
        find.byTooltip('Concluir drop set da série 1 de $_supino'),
      );
      expect(device.server.setBodies, isEmpty);

      await device.close(tester);
      device.server.offline = false;
      await device.launch(tester);
      expect(find.text('Treino em andamento'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Enviadas ao reabrir: a série e o drop, que aponta para ela pelo id do app.
      expect(device.server.setBodies, [
        {'kind': 'working', 'reps': 8, 'load_kg': 60.0},
        {
          'kind': 'drop',
          'reps': 6,
          'load_kg': 47.5,
          'parent_set_id': 'serie-1',
        },
      ]);
      await _tap(tester, find.text('Treino em andamento'));
      expect(_done(1), findsOneWidget);
      expect(find.textContaining('guardada no aparelho'), findsNothing);
    },
  );

  testWidgets('resposta perdida: o reenvio não duplica a série', (
    tester,
  ) async {
    final device = _Device();
    await device.launch(tester);
    await _startTemplate(tester);

    device.server.loseNextSetResponse = true;
    await _tap(tester, _check(1));
    expect(_pending(1), findsOneWidget);

    await _tap(tester, find.widgetWithText(TextButton, 'Tentar agora'));
    expect(device.server.resentSets, 1);
    final entry =
        (device.server.session!['exercises']! as List).first
            as Map<String, Object?>;
    final sets = entry['sets']! as List<Object?>;
    expect(sets, hasLength(1));
    expect(_done(1), findsOneWidget);
  });

  testWidgets(
    'corrigir ou desfazer uma série ainda na fila não chama o servidor',
    (tester) async {
      final device = _Device();
      await device.launch(tester);
      await _startTemplate(tester);

      device.server.offline = true;
      await _tap(tester, _check(1));
      await _tap(tester, _check(2));
      // Corrige a 1ª no campo: o envio pendente é que muda.
      await tester.enterText(_reps(0), '12');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      // Desfaz a 2ª: sai da fila.
      await _tap(tester, _pending(2));
      expect(
        find.textContaining('1 alteração guardada no aparelho'),
        findsOneWidget,
      );

      device.server.offline = false;
      await _tap(tester, find.widgetWithText(TextButton, 'Tentar agora'));
      expect(device.server.setBodies, [
        {'kind': 'working', 'reps': 12, 'load_kg': 60.0},
      ]);
    },
  );

  testWidgets('finalizar espera as séries guardadas chegarem ao servidor', (
    tester,
  ) async {
    final device = _Device();
    await device.launch(tester);
    await _startTemplate(tester);

    device.server.offline = true;
    await _tap(tester, _check(1));
    await _tap(tester, find.widgetWithText(FilledButton, 'Finalizar treino'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Salvar treino'));
    expect(
      find.textContaining('precisam ser enviadas antes de finalizar'),
      findsOneWidget,
    );
    expect(device.server.finishedSessions, isEmpty);

    device.server.offline = false;
    // O aviso cobre o botão de finalizar: fecha antes de tentar de novo.
    ScaffoldMessenger.of(tester.element(find.text('Finalizar treino')))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await _tap(tester, find.widgetWithText(FilledButton, 'Finalizar treino'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Salvar treino'));
    expect(device.server.setBodies, hasLength(1));
    expect(device.server.finishedSessions, hasLength(1));
    // Rascunho apagado: não há mais treino aberto.
    expect(device.drafts.drafts, isEmpty);
  });
}
