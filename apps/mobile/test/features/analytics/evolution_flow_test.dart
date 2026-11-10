import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/analytics/domain/analytics.dart';
import 'package:evofit/features/sessions/data/session_draft.dart';
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

Future<void> _openEvolution(WidgetTester tester) async {
  final card = find.text('Evolução');
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void _withData(FakeAuthServer server) {
  server
    ..analyticsOverview = FakeAuthServer.overview(
      sessions: 6,
      activeDays: 5,
      durationS: 4 * 3600 + 30 * 60,
      weeklyTarget: 3,
      activeWeeks: 4,
      weeksOnTarget: 2,
      streak: 3,
      modalities: [
        {
          'modality': 'strength',
          'sessions': 3,
          'duration_s': 9000,
          'distance_m': null,
          'sets': 42,
          'volume_kg': 12345.5,
        },
        {
          'modality': 'run',
          'sessions': 3,
          'duration_s': 7200,
          'distance_m': 20000,
          'sets': null,
          'volume_kg': null,
        },
      ],
    )
    ..comparisons = {
      'sessions': FakeAuthServer.comparison(4, 6, percent: 50),
      'duration_s': FakeAuthServer.comparison(5 * 3600, 4.5 * 3600),
    }
    ..runEndurance = FakeAuthServer.endurance(
      sessions: 3,
      distanceM: 20000,
      paceSPerKm: 360,
      trend: 'up',
    );
}

void main() {
  group('textos', () {
    test('comparação: percentual só com base válida', () {
      String sessions(Comparison c) =>
          describeComparison(c, 30, unit: (v) => '${v.round()}');

      expect(
        sessions(
          const Comparison(
            previous: 4,
            current: 6,
            difference: 2,
            percent: 50,
            better: 'b',
          ),
        ),
        '+2 (+50%) vs. 30 dias anteriores',
      );
      // De 0 para 3: sem percentual (não é "+∞%").
      expect(
        sessions(
          const Comparison(previous: 0, current: 3, difference: 3, better: 'b'),
        ),
        '+3 vs. 30 dias anteriores',
      );
      expect(
        sessions(
          const Comparison(
            previous: 4,
            current: 3,
            difference: -1,
            percent: -25,
            better: 'a',
          ),
        ),
        '−1 (−25%) vs. 30 dias anteriores',
      );
      expect(
        sessions(
          const Comparison(
            previous: 2,
            current: 2,
            difference: 0,
            percent: 0,
            better: 'same',
          ),
        ),
        'Igual aos 30 dias anteriores.',
      );
      expect(
        sessions(const Comparison(previous: null, current: null)),
        'Sem dados para comparar.',
      );
    });

    test('tempo total e períodos', () {
      expect(formatTotalDuration(0), '0 min');
      expect(formatTotalDuration(45 * 60), '45 min');
      expect(formatTotalDuration(2 * 3600 + 5 * 60), '2 h 05 min');
      expect(formatTotalDuration(3 * 3600), '3 h');

      const period = AnalyticsPeriod(7);
      expect(period.to.difference(period.from).inDays, 6);
      expect(period.from.difference(period.previousTo).inDays, 1);
      expect(period.previousTo.difference(period.previousFrom).inDays, 6);
    });
  });

  testWidgets('sem registros, explica o que vai aparecer', (tester) async {
    final server = await _pumpSignedIn(tester);
    await _openEvolution(tester);

    expect(find.text('Nada registrado em 30 dias'), findsOneWidget);
    // Período padrão: os últimos 30 dias até hoje.
    final today = DateTime.now();
    final from = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 29));
    expect(
      server.analyticsQueries.first,
      'overview?from=${apiDate(from)}&to=${apiDate(today)}',
    );
  });

  testWidgets('mostra frequência, comparação, consistência e modalidades', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester, setUp: _withData);
    await _openEvolution(tester);

    expect(find.text('6'), findsOneWidget);
    expect(find.text('+2 (+50%) vs. 30 dias anteriores'), findsOneWidget);
    expect(find.text('4 h 30 min'), findsOneWidget);
    // Sem percentual vindo da API, a frase não inventa um.
    expect(find.text('−30 min vs. 30 dias anteriores'), findsOneWidget);
    expect(find.text('5 de 30'), findsOneWidget);

    await _scrollTo(tester, find.text('Sequência atual: 3 semanas seguidas'));
    expect(find.text('4 de 5 semanas com treino'), findsOneWidget);
    expect(
      find.text('2 com 3 dias ou mais (sua meta no perfil)'),
      findsOneWidget,
    );

    await _scrollTo(tester, find.text('Distância semanal subindo'));
    expect(
      find.text('3 vezes · 2 h 30 min · 42 séries · 12346 kg'),
      findsOneWidget,
    );
    expect(find.text('3 vezes · 2 h · 20 km'), findsOneWidget);
    expect(find.text('20 km · pace médio 6:00 /km'), findsOneWidget);

    // O período anterior tem o mesmo tamanho e termina na véspera do atual.
    final compare = server.analyticsQueries.firstWhere(
      (q) => q.startsWith('compare?metric=sessions'),
    );
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    expect(
      compare,
      'compare?metric=sessions'
      '&a_from=${apiDate(today.subtract(const Duration(days: 59)))}'
      '&a_to=${apiDate(today.subtract(const Duration(days: 30)))}'
      '&b_from=${apiDate(today.subtract(const Duration(days: 29)))}'
      '&b_to=${apiDate(today)}',
    );
    expect(
      server.analyticsQueries.where((q) => q.startsWith('endurance')),
      hasLength(1),
    );
  });

  testWidgets('trocar o período busca de novo', (tester) async {
    final server = await _pumpSignedIn(tester, setUp: _withData);
    await _openEvolution(tester);
    final before = server.analyticsQueries.length;

    await tester.tap(find.text('7 dias'));
    await tester.pumpAndSettle();

    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    expect(
      server.analyticsQueries.skip(before).first,
      'overview?from=${apiDate(today.subtract(const Duration(days: 6)))}'
      '&to=${apiDate(today)}',
    );
    expect(find.text('+2 (+50%) vs. 7 dias anteriores'), findsOneWidget);
  });

  testWidgets('sem corrida no período, não busca a resistência', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (server) => server.analyticsOverview = FakeAuthServer.overview(
        sessions: 1,
        activeDays: 1,
        durationS: 1800,
        activeWeeks: 1,
        streak: 1,
        modalities: [
          {
            'modality': 'walk',
            'sessions': 1,
            'duration_s': 1800,
            'distance_m': null,
            'sets': null,
            'volume_kg': null,
          },
        ],
      ),
    );
    await _openEvolution(tester);

    await _scrollTo(tester, find.text('Caminhada'));
    expect(find.text('1 vez · 30 min'), findsOneWidget);
    expect(find.text('Corrida'), findsNothing);
    expect(
      server.analyticsQueries.where((q) => q.startsWith('endurance')),
      isEmpty,
    );
  });
}
