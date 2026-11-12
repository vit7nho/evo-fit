import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/home/domain/dashboard.dart';
import 'package:evofit/features/home/presentation/dashboard_sections.dart';
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

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Map<String, Object?> _goal(
  String id,
  String kind,
  String title,
  String summary, {
  Map<String, Object?>? progress,
}) => {
  'id': id,
  'kind': kind,
  'title': title,
  'summary': summary,
  'target_date': null,
  'priority': 1,
  'progress': progress,
};

Map<String, Object?> _progress(
  num? current,
  num target,
  String unit, {
  num? ratio,
  bool achieved = false,
  bool lowerIsBetter = false,
}) => {
  'current': current,
  'target': target,
  'unit': unit,
  'ratio': ratio,
  'achieved': achieved,
  'lower_is_better': lowerIsBetter,
  'basis': 'dos registros',
};

/// Quem quer ganhar massa: musculação e Meu Corpo no topo, depois a corrida.
Map<String, Object?> _muscleDashboard() => FakeAuthServer.emptyDashboard(
  objective: 'gain_muscle',
  objectiveLabel: 'Ganhar massa muscular',
  week: FakeAuthServer.dashboardWeek(
    sessions: 3,
    activeDays: 3,
    durationS: 2 * 3600 + 15 * 60,
    weeklyTarget: 3,
    previousActiveDays: 2,
    streakWeeks: 4,
  ),
  focus: [
    {
      'kind': 'strength',
      'strength': {
        'sessions': 2,
        'sets': 24,
        'volume_kg': 5400.0,
        'previous_sets': 18,
        'previous_volume_kg': 4100.0,
      },
    },
    {
      'kind': 'body',
      'body': {
        'methodology_version': 'v2',
        'period_days': 30,
        'least': [
          {
            'muscle_id': 'calves',
            'name': 'Panturrilhas',
            'weighted_sets_per_week': 0,
          },
          {
            'muscle_id': 'forearms',
            'name': 'Antebraços',
            'weighted_sets_per_week': 0,
          },
        ],
        'untrained': 2,
      },
    },
    {
      'kind': 'endurance',
      'endurance': {
        'modality': 'run',
        'sessions': 1,
        'duration_s': 1800,
        'distance_m': 5000,
        'previous_distance_m': 0,
        'pace_s_per_km': 360,
        'speed_kmh': 10.0,
        'pace_s_per_100m': null,
      },
    },
  ],
  goals: [
    _goal(
      'g1',
      'strength',
      'Supino 80 kg',
      'Supino: 80 kg × 8',
      progress: _progress(60, 80, 'kg', ratio: 0.75),
    ),
    _goal(
      'g2',
      'run_time',
      '5 km em 25 min',
      '5 km em 25:00',
      progress: _progress(1650, 1500, 's', ratio: 0.9091, lowerIsBetter: true),
    ),
    _goal('g3', 'custom', 'Dormir melhor', 'Dormir melhor'),
  ],
  activeGoals: 5,
  lastRecord: {
    'modality': 'strength',
    'title': 'Treino A',
    'day': '2026-11-10',
    'duration_s': 3000,
    'distance_m': null,
    'sets': 12,
    'volume_kg': 2700.0,
  },
);

void main() {
  testWidgets('conta nova: a semana zerada, sem foco nem metas, e os atalhos', (
    tester,
  ) async {
    final server = await _pumpSignedIn(tester);

    expect(server.dashboardCalls, 1);
    expect(find.text('Esta semana'), findsOneWidget);
    expect(find.text('0 dias ativos'), findsOneWidget);
    expect(find.text('Seu foco'), findsNothing);
    await _scrollTo(tester, find.text('Atalhos'));
    expect(find.text('Último registro'), findsNothing);
  });

  testWidgets('mostra a semana, o foco pelo objetivo, as metas e o último', (
    tester,
  ) async {
    await _pumpSignedIn(
      tester,
      setUp: (server) => server.dashboard = _muscleDashboard(),
    );

    // Tela alta: o painel inteiro fica montado (a lista só monta o que está perto).
    tester.view.physicalSize = const Size(1080, 9000);
    await tester.pumpAndSettle();
    expect(find.text('Seu foco: Ganhar massa muscular.'), findsOneWidget);
    expect(find.text('3 de 3 dias'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('3 treinos e atividades · 2 h 15 min'), findsOneWidget);
    expect(
      find.text('Semana passada: 2 dias ativos · sequência de 4 semanas'),
      findsOneWidget,
    );

    await _scrollTo(tester, find.text('Corrida · últimos 7 dias'));
    // A ordem vem da API: musculação, Meu Corpo, corrida.
    final titles = [
      'Musculação · últimos 7 dias',
      'Meu Corpo · 30 dias',
      'Corrida · últimos 7 dias',
    ].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
    expect(titles, orderedEquals([...titles]..sort()));
    expect(find.text('24 séries · 5.400 kg'), findsOneWidget);
    expect(
      find.text('7 dias anteriores: 18 séries · 4.100 kg'),
      findsOneWidget,
    );
    expect(
      find.text('Sem nenhuma série em 30 dias: Panturrilhas e Antebraços'),
      findsOneWidget,
    );
    expect(find.text('5 km · pace 6:00 /km'), findsOneWidget);
    expect(find.text('Sem distância nos 7 dias anteriores'), findsOneWidget);

    await _scrollTo(tester, find.text('Dormir melhor').first);
    expect(find.text('Ver as 5'), findsOneWidget);
    expect(find.text('60 de 80 kg'), findsOneWidget);
    expect(find.text('27:30 (alvo 25:00)'), findsOneWidget);

    await _scrollTo(tester, find.text('Treino A'));
    expect(find.text('12 séries · 2.700 kg · 50 min'), findsOneWidget);
    expect(find.text('Ontem'), findsOneWidget);
  });

  testWidgets('tocar num cartão abre a tela e, na volta, o painel é refeito', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (server) => server.dashboard = _muscleDashboard(),
    );
    expect(server.dashboardCalls, 1);

    await _scrollTo(tester, find.text('Meu Corpo · 30 dias'));
    await tester.tap(find.text('Meu Corpo · 30 dias'));
    await tester.pumpAndSettle();
    expect(find.text('Frente'), findsOneWidget);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(server.dashboardCalls, 2);
  });

  testWidgets('erro no painel: explica, tenta de novo, e os atalhos ficam', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (server) => server.failDashboard = true,
    );

    expect(find.text('Não foi possível montar o seu painel'), findsOneWidget);
    await _scrollTo(tester, find.text('Atalhos'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(server.dashboardCalls, 2);
    expect(find.text('Esta semana'), findsOneWidget);
  });

  group('textos', () {
    test('semana e foco', () {
      const week = DashboardWeek(
        sessions: 1,
        activeDays: 1,
        durationS: 0,
        previousSessions: 0,
        previousActiveDays: 0,
        streakWeeks: 1,
      );
      expect(weekHeadline(week), '1 dia ativo');
      expect(weekDetail(week), '1 treino ou atividade');
      expect(
        weekHistory(week),
        'Semana passada: 0 dias ativos · sequência de 1 semana',
      );

      expect(
        strengthHeadline(
          const StrengthFocus(
            sessions: 0,
            sets: 0,
            volumeKg: 0,
            previousSets: 1,
            previousVolumeKg: 0,
          ),
        ),
        'Nenhuma série nos últimos 7 dias',
      );

      BodyFocus body(int untrained, List<(String, double)> least) => BodyFocus(
        periodDays: 30,
        untrained: untrained,
        least: [for (final (n, v) in least) (name: n, perWeek: v)],
      );
      expect(
        bodyHeadline(
          body(10, [
            ('Bíceps', 0),
            ('Dorsais', 0),
            ('Trapézio', 0),
            ('Oblíquos', 0),
          ]),
        ),
        '10 músculos sem nenhuma série em 30 dias, como Bíceps, Dorsais, '
        'Trapézio e Oblíquos',
      );
      expect(
        bodyHeadline(body(0, [('Abdômen', 0.47)])),
        'Menos estímulo: Abdômen (0,47 séries/semana)',
      );

      expect(
        enduranceHeadline(
          const EnduranceFocus(
            modality: 'walk',
            sessions: 2,
            durationS: 3600,
            distanceM: 0,
            previousDistanceM: 0,
          ),
        ),
        '2 vezes · 1 h',
      );
      expect(
        enduranceHeadline(
          const EnduranceFocus(
            modality: 'swim',
            sessions: 1,
            durationS: 1200,
            distanceM: 1000,
            previousDistanceM: 500,
            paceSPer100m: 120,
          ),
        ),
        '1000 m · ritmo 2:00 /100 m',
      );
    });

    test('progresso das metas', () {
      GoalProgress p(
        num? current,
        num target,
        String unit, {
        bool achieved = false,
        bool lower = false,
      }) => GoalProgress.fromJson(
        _progress(
          current,
          target,
          unit,
          achieved: achieved,
          lowerIsBetter: lower,
        ),
      );
      expect(
        goalProgressText(p(null, 10, 'km')),
        'Ainda sem registro que meça esta meta',
      );
      expect(goalProgressText(p(8, 10, 'km')), '8 de 10 km');
      expect(
        goalProgressText(p(1.5, 10, 'sets_per_week')),
        '1,5 de 10 séries/semana',
      );
      expect(
        goalProgressText(p(1, 4, 'sessions')),
        '1 treino de 4 nesta semana',
      );
      expect(
        goalProgressText(p(85, 80, 'kg', achieved: true)),
        'Alvo atingido: 85 kg',
      );
      expect(
        goalProgressText(p(1450, 1500, 's', achieved: true, lower: true)),
        'Alvo atingido: 24:10',
      );
    });
  });
}
