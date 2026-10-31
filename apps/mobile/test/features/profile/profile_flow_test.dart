import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/shared/widgets/evo_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

/// App inteiro sobre o servidor falso, com uma sessão salva (entra direto).
Future<FakeAuthServer> _pumpSignedIn(
  WidgetTester tester, {
  required bool onboarded,
  void Function(FakeAuthServer server)? setUp,
}) async {
  final server = FakeAuthServer(validRefreshToken: 'salvo');
  if (!onboarded) server.profile = FakeAuthServer.newProfile();
  setUp?.call(server);
  // Tela alta: as etapas cabem sem rolagem e os toques acertam os alvos.
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

/// Toca o cartão ou a pílula com este rótulo (cartões primeiro: um objetivo aparece
/// como cartão principal e também como pílula de objetivo secundário).
Future<void> _tapText(WidgetTester tester, String text) async {
  final card = find.widgetWithText(EvoOptionCard, text);
  final finder = card.evaluate().isNotEmpty ? card : find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _continue(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pumpAndSettle();
}

void main() {
  group('onboarding', () {
    testWidgets('conta nova abre no onboarding, não no início', (tester) async {
      await _pumpSignedIn(tester, onboarded: false);

      expect(find.text('Qual é o seu\nobjetivo?'), findsOneWidget);
      expect(find.text('Olá, Ana!'), findsNothing);
    });

    testWidgets('continuar só libera depois de escolher', (tester) async {
      await _pumpSignedIn(tester, onboarded: false);

      final button = find.widgetWithText(FilledButton, 'Continuar');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await _tapText(tester, 'Emagrecer');
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });

    testWidgets('respondendo tudo, envia um único PATCH e vai ao início', (
      tester,
    ) async {
      final server = await _pumpSignedIn(tester, onboarded: false);

      await _tapText(tester, 'Emagrecer');
      await tester.tap(
        find.widgetWithText(EvoChip, 'Saúde geral'),
      ); // secundário
      await tester.pumpAndSettle();
      await _continue(tester, 'Continuar');

      await _tapText(tester, 'Caminhada');
      await _tapText(tester, 'Iniciante');
      await _continue(tester, 'Continuar');

      await tester.tap(find.bySemanticsLabel('4 dias por semana'));
      await tester.pumpAndSettle();
      await _tapText(tester, '30 min');
      await _tapText(tester, 'Elásticos');
      await _continue(tester, 'Continuar');

      await _continue(tester, 'Concluir'); // saúde: sem autorização

      expect(find.text('Olá, Ana!'), findsOneWidget);
      expect(server.consentCalls, isEmpty);
      expect(server.patches, hasLength(1));
      expect(server.patches.single, {
        'primary_objective': 'lose_weight',
        'secondary_objectives': ['general_health'],
        'preferred_modalities': ['walk'],
        'experience_level': 'beginner',
        'weekly_availability': {'days_per_week': 4, 'minutes_per_session': 30},
        'equipment': ['bands'],
        'onboarding_completed': true,
      });
    });

    testWidgets('pulando tudo, conclui sem respostas', (tester) async {
      final server = await _pumpSignedIn(tester, onboarded: false);

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Pular'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Olá, Ana!'), findsOneWidget);
      expect(server.patches.single['onboarding_completed'], isTrue);
      expect(server.patches.single.containsKey('primary_objective'), isFalse);
    });

    testWidgets('dados de saúde pedem consentimento antes de serem enviados', (
      tester,
    ) async {
      final server = await _pumpSignedIn(tester, onboarded: false);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Pular'));
        await tester.pumpAndSettle();
      }

      // Sem autorizar, as opções de limitação nem aparecem.
      expect(find.text('Joelho'), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await _tapText(tester, 'Joelho');
      await _continue(tester, 'Concluir');

      expect(find.text('Olá, Ana!'), findsOneWidget);
      expect(server.consentCalls, ['PUT health_data']);
      expect(server.patches.single['limitation_tags'], ['knee']);
    });

    testWidgets('voltar retorna ao passo anterior mantendo a escolha', (
      tester,
    ) async {
      await _pumpSignedIn(tester, onboarded: false);
      await _tapText(tester, 'Emagrecer');
      await _continue(tester, 'Continuar');
      expect(find.text('Como você se\nexercita?'), findsOneWidget);

      await tester.tap(find.byTooltip('Passo anterior'));
      await tester.pumpAndSettle();

      final button = find.widgetWithText(FilledButton, 'Continuar');
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });
  });

  group('perfil', () {
    Future<void> openProfile(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Perfil'));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra o resumo de cada seção com os rótulos', (tester) async {
      await _pumpSignedIn(tester, onboarded: true);
      await openProfile(tester);

      expect(find.text('Ganhar massa muscular'), findsOneWidget);
      expect(find.text('Musculação'), findsOneWidget);
      expect(find.text('3x por semana · 45 min'), findsOneWidget);
      expect(find.text('Não autorizado'), findsOneWidget);
    });

    testWidgets('editar a rotina salva só essa seção e atualiza o resumo', (
      tester,
    ) async {
      final server = await _pumpSignedIn(tester, onboarded: true);
      await openProfile(tester);

      await _tapText(tester, 'Rotina');
      await tester.tap(find.bySemanticsLabel('5 dias por semana'));
      await tester.pumpAndSettle();
      await _continue(tester, 'Salvar');

      expect(server.patches.single.keys, {'weekly_availability', 'equipment'});
      expect(find.text('Perfil atualizado'), findsOneWidget);
      expect(find.text('5x por semana · 45 min'), findsOneWidget);
    });

    testWidgets('revogar os dados de saúde pede confirmação e apaga', (
      tester,
    ) async {
      final server = await _pumpSignedIn(
        tester,
        onboarded: true,
        setUp: (s) => s
          ..consents.add('health_data')
          ..profile['limitation_tags'] = ['knee'],
      );
      await openProfile(tester);
      await _tapText(tester, 'Saúde');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await _continue(tester, 'Salvar');
      expect(find.text('Revogar dados de saúde?'), findsOneWidget);

      await tester.tap(find.text('Revogar e apagar'));
      await tester.pumpAndSettle();

      expect(server.consentCalls, ['DELETE health_data']);
      expect(server.patches, isEmpty);
      expect(find.text('Não autorizado'), findsOneWidget);
    });

    testWidgets('cancelar a revogação não altera nada', (tester) async {
      final server = await _pumpSignedIn(
        tester,
        onboarded: true,
        setUp: (s) => s.consents.add('health_data'),
      );
      await openProfile(tester);
      await _tapText(tester, 'Saúde');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await _continue(tester, 'Salvar');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(server.consentCalls, isEmpty);
    });

    testWidgets('consentimento de IA liga direto no perfil', (tester) async {
      final server = await _pumpSignedIn(tester, onboarded: true);
      await openProfile(tester);

      final aiSwitch = find.byType(Switch);
      await tester.ensureVisible(aiSwitch);
      await tester.pumpAndSettle();
      await tester.tap(aiSwitch);
      await tester.pumpAndSettle();

      expect(server.consentCalls, ['PUT ai_processing']);
      expect(tester.widget<Switch>(aiSwitch).value, isTrue);
    });
  });
}
