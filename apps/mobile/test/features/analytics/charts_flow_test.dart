import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/analytics/domain/analytics.dart';
import 'package:evofit/features/analytics/domain/compare.dart';
import 'package:evofit/features/analytics/presentation/charts.dart';
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

Future<void> _openEvolution(WidgetTester tester) async {
  await _scrollTo(tester, find.text('Evolução'));
  await tester.tap(find.text('Evolução'));
  await tester.pumpAndSettle();
}

List<double?> _values(WidgetTester tester, String key) {
  final widget = tester.widget(find.byKey(ValueKey(key)));
  final points = switch (widget) {
    EvoBarChart(:final points) => points,
    EvoLineChart(:final points) => points,
    _ => throw StateError('não é gráfico: $widget'),
  };
  return [for (final p in points) p.value];
}

Map<String, Object?> _modality(String code, {int? distanceM}) => {
  'modality': code,
  'sessions': 2,
  'duration_s': 3600,
  'distance_m': distanceM,
  'sets': code == 'strength' ? 30 : null,
  'volume_kg': code == 'strength' ? 3300.0 : null,
};

void _withData(FakeAuthServer server) {
  server
    ..analyticsOverview = FakeAuthServer.overview(
      sessions: 8,
      activeDays: 7,
      durationS: 8 * 3600,
      activeWeeks: 4,
      streak: 2,
      weekSessions: [2, 3, 0, 1, 2],
      weekSets: [10, 12, 0, 0, 8],
      weekVolume: [1000, 1500, 0, 0, 800],
      modalities: [_modality('strength'), _modality('run', distanceM: 20000)],
    )
    ..runEndurance = FakeAuthServer.endurance(
      sessions: 3,
      distanceM: 20000,
      paceSPerKm: 345,
      trend: 'up',
      weeks: [
        FakeAuthServer.enduranceWeek('2026-10-05', distanceM: 0),
        FakeAuthServer.enduranceWeek(
          '2026-10-12',
          distanceM: 8000,
          paceSPerKm: 360,
        ),
        FakeAuthServer.enduranceWeek(
          '2026-10-19',
          distanceM: 12000,
          paceSPerKm: 330,
        ),
      ],
    );
}

DateTime get _today {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _range(int fromAgo, int toAgo) =>
    'from=${apiDate(_today.subtract(Duration(days: fromAgo)))}'
    '&to=${apiDate(_today.subtract(Duration(days: toAgo)))}';

void main() {
  testWidgets('Por semana: uma barra por semana e troca de indicador', (
    tester,
  ) async {
    await _pumpSignedIn(tester, setUp: _withData);
    await _openEvolution(tester);
    await _scrollTo(tester, find.byKey(const ValueKey('week-chart')));

    expect(_values(tester, 'week-chart'), [2, 3, 0, 1, 2]);
    final chart = tester.widget<EvoBarChart>(
      find.byKey(const ValueKey('week-chart')),
    );
    expect(chart.title, 'Treinos por semana');
    expect(chart.format(3), '3 treinos');
    expect(chart.points[1].spoken, startsWith('Semana de '));

    await tester.ensureVisible(find.text('Volume'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volume'));
    await tester.pumpAndSettle();
    expect(_values(tester, 'week-chart'), [1000, 1500, 0, 0, 800]);
    await tester.ensureVisible(find.text('Tempo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tempo'));
    await tester.pumpAndSettle();
    expect(_values(tester, 'week-chart'), [60, 60, 60, 60, 0]);

    // Corrida: distância por semana e o pace só das semanas com distância.
    await _scrollTo(tester, find.byKey(const ValueKey('rhythm-run')));
    expect(_values(tester, 'distance-run'), [0, 8000, 12000]);
    expect(_values(tester, 'rhythm-run'), [null, 360, 330]);
    expect(find.text('Pace por semana (menor é melhor)'), findsOneWidget);
    expect(find.text('20 km · pace médio 5:45 /km'), findsOneWidget);
  });

  testWidgets('sem musculação, só Treinos e Tempo; ritmo pede 2 semanas', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (server) => server
        ..analyticsOverview = FakeAuthServer.overview(
          sessions: 2,
          activeDays: 2,
          durationS: 3600,
          activeWeeks: 1,
          modalities: [
            _modality('swim', distanceM: 1500),
            _modality('walk'), // sem distância: não busca
          ],
        )
        ..enduranceByModality = {
          'swim': FakeAuthServer.endurance(
            modality: 'swim',
            sessions: 2,
            distanceM: 1500,
            paceSPer100m: 120,
            weeks: [
              FakeAuthServer.enduranceWeek(
                '2026-10-05',
                distanceM: 1500,
                paceSPer100m: 120,
              ),
            ],
          ),
        },
    );
    await _openEvolution(tester);

    await _scrollTo(tester, find.byKey(const ValueKey('week-chart')));
    expect(find.text('Volume'), findsNothing);
    expect(find.text('Séries'), findsNothing);

    await _scrollTo(tester, find.byKey(const ValueKey('distance-swim')));
    expect(find.text('1500 m · ritmo médio 2:00 /100 m'), findsOneWidget);
    expect(find.byKey(const ValueKey('rhythm-swim')), findsNothing);
    expect(
      server.analyticsQueries.where((q) => q.startsWith('endurance')).toList(),
      [startsWith('endurance?modality=swim&')],
    );
  });

  testWidgets('Comparativos: A contra B, indicador por indicador', (
    tester,
  ) async {
    final server = await _pumpSignedIn(
      tester,
      setUp: (server) {
        _withData(server);
        server.comparisons = {
          'sessions': FakeAuthServer.comparison(4, 6, percent: 50),
          'strength_volume_kg': FakeAuthServer.comparison(
            2000,
            1500,
            percent: -25,
            metric: 'strength_volume_kg',
          ),
          'pace_s_per_km:run': FakeAuthServer.comparison(
            360,
            330,
            percent: -8.33,
            metric: 'pace_s_per_km',
            modality: 'run',
          ),
        };
      },
    );
    await _openEvolution(tester);
    final before = server.analyticsQueries.length;
    await tester.tap(find.text('Comparar'));
    await tester.pumpAndSettle();

    // Padrão: os últimos 30 dias (B) contra os 30 anteriores (A).
    final queries = server.analyticsQueries.skip(before).toList();
    expect(queries.take(2), [
      'overview?${_range(59, 30)}',
      'overview?${_range(29, 0)}',
    ]);
    final a = 'a_from=${apiDate(_today.subtract(const Duration(days: 59)))}';
    expect(
      queries.where((q) => q.startsWith('compare')).map((q) => q.split('&')[0]),
      [
        'compare?metric=sessions',
        'compare?metric=active_days',
        'compare?metric=duration_s',
        'compare?metric=strength_sets',
        'compare?metric=strength_volume_kg',
        'compare?metric=distance_m',
        'compare?metric=pace_s_per_km',
      ],
    );
    expect(queries.last, contains(a));
    expect(queries.last, contains('modality=run'));

    expect(find.text('Treinos e atividades'), findsOneWidget);
    expect(find.text('+2 (+50%) no período B'), findsOneWidget);
    await _scrollTo(tester, find.text('Pace médio · Corrida'));
    expect(find.text('−500 kg (−25%) no período B'), findsOneWidget);
    expect(
      find.text('−0:30 /km (−8%) no período B · mais rápido'),
      findsOneWidget,
    );
    expect(find.text('Sem dados para comparar.'), findsWidgets);

    // Outro atalho busca de novo, com os dois períodos de 7 dias.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    final mark = server.analyticsQueries.length;
    await tester.tap(find.text('7 dias'));
    await tester.pumpAndSettle();
    expect(server.analyticsQueries.skip(mark).take(2), [
      'overview?${_range(13, 7)}',
      'overview?${_range(6, 0)}',
    ]);
  });

  testWidgets('Comparativos sem registros explicam', (tester) async {
    await _pumpSignedIn(
      tester,
      setUp: (server) => server.analyticsOverview = FakeAuthServer.overview(
        sessions: 1,
        activeDays: 1,
        durationS: 600,
        activeWeeks: 1,
        modalities: [_modality('walk')],
      ),
    );
    await _openEvolution(tester);
    await tester.tap(find.text('Comparar'));
    await tester.pumpAndSettle();
    expect(find.text('Nada registrado nos dois períodos'), findsOneWidget);
  });

  group('regras', () {
    test('atalhos de período', () {
      (String, String) span(AnalyticsPeriod p) =>
          (apiDate(p.from), apiDate(p.to));

      final week = ComparePreset.week.pair(DateTime(2026, 11, 11, 15))!;
      expect(span(week.b), ('2026-11-05', '2026-11-11'));
      expect(span(week.a), ('2026-10-29', '2026-11-04'));

      // Mês até hoje contra o mesmo trecho do mês passado...
      final month = ComparePreset.calendarMonth.pair(DateTime(2026, 11, 11))!;
      expect(span(month.b), ('2026-11-01', '2026-11-11'));
      expect(span(month.a), ('2026-10-01', '2026-10-11'));
      // ...cortado no último dia quando o mês passado é mais curto.
      final march = ComparePreset.calendarMonth.pair(DateTime(2026, 3, 31))!;
      expect(span(march.a), ('2026-02-01', '2026-02-28'));
      // Janeiro compara com dezembro do ano anterior.
      final january = ComparePreset.calendarMonth.pair(DateTime(2027, 1, 5))!;
      expect(span(january.a), ('2026-12-01', '2026-12-05'));

      expect(ComparePreset.custom.pair(DateTime(2026, 11, 11)), isNull);
    });

    test('teto do eixo e frases', () {
      expect(niceCeiling(0), 1);
      expect(niceCeiling(3), 5);
      expect(niceCeiling(12), 20);
      expect(niceCeiling(1500), 2000);
      expect(niceCeiling(0.4), 0.5);

      // Contagens: teto par, marca do meio inteira.
      expect(wholeCeiling(0), 2);
      expect(wholeCeiling(3), 4);
      expect(wholeCeiling(4), 4);
      expect(wholeCeiling(12.5), 14);

      // Linha: perto dos valores, com passos redondos.
      const time = EvoLineChart.timeSteps;
      const decimal = EvoLineChart.decimalSteps;
      // Pace de 6:24 a 5:24 /km: marcas 5:00, 6:00 e 7:00.
      expect(lineAxis([384, 360, 345, 324], time), (300, 420));
      expect(lineAxis([55, 57.5, 60, 62.5], decimal), (50, 70));
      expect(lineAxis([76.5, 80], decimal), (75, 85));
      expect(lineAxis([60, 60], decimal), (59.5, 60.5));
      expect(lineAxis([], decimal), (0, 1));
      expect(axisDate(DateTime(2026, 10, 5)), '5/10');

      expect(
        describeChart('Treinos por semana', const [
          ChartPoint(label: 'a', spoken: 'Semana A', value: 2),
          ChartPoint(label: 'b', spoken: 'Semana B', value: null),
        ], (v) => '${v.round()}'),
        'Treinos por semana. Semana A: 2; Semana B: sem dado.',
      );

      CompareRow row(num? a, num? b, String metric, {num? percent}) =>
          CompareRow(
            Comparison.fromJson(
              FakeAuthServer.comparison(a, b, metric: metric, percent: percent),
            ),
          );
      expect(
        describePairDifference(row(null, 3, 'sessions')),
        'Sem dados para comparar.',
      );
      expect(
        describePairDifference(row(2, 2, 'sessions')),
        'Igual nos dois períodos.',
      );
      // De 0 para 3, sem percentual.
      expect(describePairDifference(row(0, 3, 'sessions')), '+3 no período B');
      expect(
        describePairDifference(row(3600, 5400, 'duration_s', percent: 50)),
        '+30 min (+50%) no período B',
      );
      expect(
        describePairDifference(row(300, 330, 'pace_s_per_km', percent: 10)),
        '+0:30 /km (+10%) no período B · mais lento',
      );
    });
  });
}
