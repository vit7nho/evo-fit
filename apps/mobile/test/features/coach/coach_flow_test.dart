import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/coach/domain/coach.dart';
import 'package:evofit/features/sessions/data/session_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

const _lastSession = 'O que fiz na minha última sessão?';

Future<FakeAuthServer> _pumpSignedIn(
  WidgetTester tester, {
  bool consented = true,
  void Function(FakeAuthServer server)? setUp,
}) async {
  final server = FakeAuthServer(validRefreshToken: 'salvo');
  if (consented) server.consents.add('ai_processing');
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

Future<void> _openAssistant(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Assistente'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await _tap(tester, find.text('Assistente'));
}

Future<void> _newConversation(WidgetTester tester) async {
  await _openAssistant(tester);
  await _tap(tester, find.text('Nova conversa'));
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await _tap(tester, find.byTooltip('Enviar pergunta'));
}

void main() {
  testWidgets('pergunta sugerida: a resposta mostra o que foi consultado', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) => s
        ..coachSimulated = false
        ..coachReplies.add((
          'Na última sessão (Peito, 01/11) você fez 2 séries de supino, com '
              'volume calculado de 1.200 kg.',
          ['get_workout_history', 'get_session_detail', 'get_workout_history'],
        )),
    );
    await _openAssistant(tester);
    expect(find.text('Nenhuma conversa ainda'), findsOneWidget);
    await _tap(tester, find.text('Nova conversa'));

    expect(server.conversationBodies.single, {'scope': 'global'});
    expect(find.text('Conversa geral'), findsWidgets);
    await _tap(tester, find.text(_lastSession));

    expect(server.questions, [_lastSession]);
    expect(find.textContaining('1.200 kg'), findsOneWidget);
    // Os nomes que a pessoa reconhece, sem repetição.
    expect(find.text('Consultou: treinos e detalhe do treino'), findsOneWidget);
    expect(find.text('Restam 29 perguntas hoje.'), findsOneWidget);
    // As sugestões somem depois da primeira pergunta; não é modo simulado.
    expect(find.text('Como foi minha semana de treinos?'), findsNothing);
    expect(find.textContaining('Modo de demonstração'), findsNothing);

    // De volta à lista, a conversa leva a pergunta como título.
    await _tap(tester, find.byTooltip('Voltar'));
    expect(find.text(_lastSession), findsOneWidget);
    expect(find.textContaining('Conversa geral ·'), findsOneWidget);
  });

  testWidgets('modo de demonstração avisa que a resposta é simulada', (
    tester,
  ) async {
    await _pumpSignedIn(tester);
    await _newConversation(tester);
    await _type(tester, 'Como estou indo?');

    expect(find.text(FakeAuthServer.demoReply), findsOneWidget);
    expect(find.textContaining('Modo de demonstração'), findsOneWidget);
    expect(find.text('Como estou indo?'), findsOneWidget);
  });

  testWidgets('sem consentimento, autoriza antes de perguntar', (tester) async {
    final server = await _pumpSignedIn(tester, consented: false);
    await _newConversation(tester);

    expect(find.text('Autorize as análises com IA'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await _tap(tester, find.text('Autorizar e continuar'));

    expect(server.consentCalls, ['PUT ai_processing']);
    expect(find.text('Autorize as análises com IA'), findsNothing);
    await _type(tester, 'Oi');
    expect(server.questions, ['Oi']);
  });

  testWidgets('erro da IA mostra o motivo e devolve a pergunta ao campo', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) => s.coachReplies.addAll([
        FakeAuthServer.problem(
          429,
          'ai_per_minute_limit',
          'Muitas perguntas em sequência. Aguarde um minuto e tente de novo.',
        ),
        FakeAuthServer.problem(
          503,
          'ai_unavailable',
          'A IA está indisponível no momento. Tente de novo em alguns minutos.',
        ),
      ]),
    );
    await _newConversation(tester);
    await _type(tester, 'Quanto corri?');

    expect(
      find.text(
        'Muitas perguntas em sequência. Aguarde um minuto e tente de novo.',
      ),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Quanto corri?');
    // A pergunta que falhou não fica na conversa.
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('Quanto corri?'),
      ),
      findsNothing,
    );

    await _tap(tester, find.byTooltip('Enviar pergunta'));
    expect(find.textContaining('indisponível no momento'), findsOneWidget);

    await _tap(tester, find.byTooltip('Enviar pergunta'));
    expect(server.questions, [
      'Quanto corri?',
      'Quanto corri?',
      'Quanto corri?',
    ]);
    expect(find.text(FakeAuthServer.demoReply), findsOneWidget);
    expect(find.textContaining('indisponível'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('a conversa reaberta mostra o histórico', (tester) async {
    await _pumpSignedIn(tester);
    await _newConversation(tester);
    await _type(tester, 'Primeira pergunta');
    await _tap(tester, find.byTooltip('Voltar'));
    await _tap(tester, find.text('Primeira pergunta'));

    expect(find.text('Primeira pergunta'), findsWidgets);
    expect(find.text(FakeAuthServer.demoReply), findsOneWidget);
  });

  testWidgets('apagar uma conversa pede confirmação', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _newConversation(tester);
    await _type(tester, 'Uma pergunta');
    await _tap(tester, find.byTooltip('Voltar'));

    await _tap(tester, find.byTooltip('Apagar conversa'));
    expect(find.text('Apagar conversa?'), findsOneWidget);
    await _tap(tester, find.text('Cancelar'));
    expect(server.conversations, hasLength(1));

    await _tap(tester, find.byTooltip('Apagar conversa'));
    await _tap(tester, find.text('Apagar'));
    expect(server.conversations, isEmpty);
    expect(find.text('Nenhuma conversa ainda'), findsOneWidget);
    expect(find.text('Conversa apagada.'), findsOneWidget);
  });

  testWidgets('conversa com foco oferece perguntar sobre tudo', (tester) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (s) => s.conversations.add({
        'id': 'foco',
        'scope': 'muscle',
        'scope_ref': {'muscle_id': 'chest'},
        'title': 'Peito · 30 dias',
        'created_at': '2026-11-24T12:00:00Z',
        'updated_at': '2026-11-24T12:00:00Z',
      }),
    );
    server.conversationMessages['foco'] = [];
    await _openAssistant(tester);
    await _tap(tester, find.text('Peito · 30 dias'));
    expect(find.text('Sobre um músculo'), findsOneWidget);

    await _tap(tester, find.text('Perguntar sobre tudo'));
    expect(server.conversationBodies.single, {'scope': 'global'});
    expect(find.text('Conversa geral'), findsWidgets);
    expect(find.text(_lastSession), findsOneWidget);
  });

  test('nomes das ferramentas na linguagem da pessoa', () {
    expect(describeTools(const []), isNull);
    expect(describeTools(const ['get_goals']), 'Consultou: metas');
    expect(
      describeTools(const [
        'get_muscle_stimulus',
        'compare_periods',
        'get_activities',
      ]),
      'Consultou: Meu Corpo, comparativos e atividades',
    );
    expect(CoachScope.of('period'), CoachScope.period);
    expect(CoachScope.of('desconhecido'), CoachScope.global);
  });

  group('propostas (4.6)', () {
    Future<FakeAuthServer> withProposal(WidgetTester tester) async {
      final server = await _pumpSignedIn(
        tester,
        setUp: (s) => s
          ..coachSimulated = false
          ..coachReplies.add((
            'Sugeri a mesa flexora; confirme abaixo.',
            ['get_templates', 'prepare_change_proposal'],
          ))
          ..nextProposals.add(FakeAuthServer.proposal('p1')),
      );
      await _newConversation(tester);
      await _type(tester, 'Adicione um exercício de posterior na ficha A');
      return server;
    }

    testWidgets('a proposta aparece com o motivo e só aplica ao confirmar', (
      tester,
    ) async {
      final server = await withProposal(tester);

      expect(find.text('Proposta · Aguardando sua resposta'), findsOneWidget);
      expect(
        find.text('Acrescentar Mesa flexora à ficha “Treino A”'),
        findsOneWidget,
      );
      expect(find.text('Séries: 3 séries de 10 a 12 reps'), findsOneWidget);
      expect(
        find.text('Motivo: Posterior de coxa sem nenhuma série em 30 dias.'),
        findsOneWidget,
      );
      expect(
        find.text('Consultou: fichas de treino e proposta de alteração'),
        findsOneWidget,
      );
      expect(server.proposalCalls, isEmpty);

      await _tap(tester, find.text('Confirmar'));
      expect(server.proposalCalls, ['accept p1']);
      expect(find.text('Proposta · Aplicada'), findsOneWidget);
      expect(find.text('Alteração aplicada.'), findsOneWidget);
      expect(find.text('Confirmar'), findsNothing);
      expect(find.text('Ver ficha'), findsOneWidget);
    });

    testWidgets('recusar não muda nada e fecha a proposta', (tester) async {
      final server = await withProposal(tester);
      await _tap(tester, find.text('Recusar'));

      expect(server.proposalCalls, ['reject p1']);
      expect(find.text('Proposta · Recusada'), findsOneWidget);
      expect(find.text('Proposta recusada. Nada mudou.'), findsOneWidget);
      expect(find.text('Confirmar'), findsNothing);
      expect(find.text('Ver ficha'), findsNothing);
    });

    testWidgets('ficha mudada depois: avisa e mostra que não foi aplicada', (
      tester,
    ) async {
      final server = await withProposal(tester);
      server.proposalErrors['p1'] = FakeAuthServer.problem(
        409,
        'proposal_stale',
        'A ficha foi alterada depois da sugestão, então nada foi aplicado. '
            'Peça à IA uma sugestão nova.',
      );
      await _tap(tester, find.text('Confirmar'));

      expect(
        find.textContaining('A ficha foi alterada depois da sugestão, então'),
        findsOneWidget,
      );
      // A conversa recarrega com o estado da API.
      expect(find.text('Proposta · Não aplicada'), findsOneWidget);
      expect(
        find.text('A ficha foi alterada depois da sugestão.'),
        findsOneWidget,
      );
      expect(find.text('Confirmar'), findsNothing);
    });
  });
}
