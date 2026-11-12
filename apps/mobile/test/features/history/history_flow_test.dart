import 'package:evofit/features/sessions/data/session_draft.dart';
import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/features/analytics/presentation/charts.dart';
import 'package:evofit/features/sessions/application/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

const _supino = 'Supino reto com barra';

Map<String, Object?> _set(
  String id,
  int position, {
  String kind = 'working',
  int reps = 10,
  double? load = 60,
  String? parent,
  bool failure = false,
}) => {
  'id': id,
  'position': position,
  'kind': kind,
  'parent_set_id': parent,
  'reps': reps,
  'load_kg': load,
  'duration_s': null,
  'rir': null,
  'rpe': null,
  'to_failure': failure,
  'completed_at': '2026-10-30T10:05:00Z',
};

/// Um treino concluído de supino: aquecimento, 62,5×8 (falha) + drop 50×6, com a
/// vez anterior (60×10, 60×8) para a comparação e um recorde de carga.
Map<String, Object?> _pastWorkout(FakeAuthServer s) {
  final template = s.templateFrom('ficha', 1, {
    'name': 'Peito',
    'notes': null,
    'groups': <Object>[],
    'items': [
      {
        'exercise_id': 'ex-supino',
        'planned_sets': [
          {'kind': 'working', 'reps_min': 8, 'reps_max': 12},
        ],
        'rest_s': 90,
        'notes': null,
        'group': null,
      },
    ],
  });
  s.previousSets = {
    'ex-supino': [
      {'kind': 'working', 'reps': 10, 'load_kg': 60, 'duration_s': null},
      {'kind': 'working', 'reps': 8, 'load_kg': 60, 'duration_s': null},
    ],
  };
  final workout = s.sessionFrom(template);
  final entry = (workout['exercises']! as List).single as Map<String, Object?>;
  entry['sets'] = [
    _set('a', 0, kind: 'warmup', reps: 15, load: 20),
    _set('b', 1, reps: 8, load: 62.5, failure: true),
    _set('c', 2, kind: 'drop', reps: 6, load: 50, parent: 'b'),
  ];
  return {
    ...workout,
    'id': 'passado-1',
    'status': 'completed',
    'elapsed_s': 2700,
    'perceived_effort': 8,
    'notes': 'Bom treino',
    'set_count': 1,
    'volume_kg': 800,
    'records': [
      {
        'exercise_id': 'ex-supino',
        'kind': 'max_load',
        'value': 62.5,
        'reps': 8,
        'load_kg': 62.5,
        'previous': 60,
      },
    ],
  };
}

Map<String, Object?> _summary(String id, String name, {int records = 0}) => {
  'id': id,
  'name': name,
  'started_at': '2026-10-30T10:00:00Z',
  'duration_s': 2700,
  'set_count': 4,
  'volume_kg': 3420,
  'exercise_count': 5,
  'exercise_names': [
    _supino,
    'Tríceps francês',
    'Agachamento livre',
    'Flexão de braços',
  ],
  'record_count': records,
};

Map<String, Object?> _ref(String id, String name) => {
  'id': id,
  'name': name,
  'equipment': 'barbell',
  'load_type': 'external',
  'is_active': true,
  'primary_muscles': ['chest'],
};

Map<String, Object?> _record(String kind, double value, {int? reps}) => {
  'kind': kind,
  'value': value,
  'reps': reps,
  'load_kg': reps == null ? null : value,
  'session_id': 'passado-1',
  'achieved_at': '2026-10-30T10:00:00Z',
};

Future<FakeAuthServer> _pump(
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
        clockTickProvider.overrideWith((ref) => const Stream.empty()),
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

/// O cartão fica mais abaixo no início (lista preguiçosa): rola até ele.
Future<void> _openHistory(WidgetTester tester) async {
  final card = find.text('Histórico');
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await _tap(tester, card);
}

void main() {
  testWidgets('lista de treinos com resumo e recordes; o detalhe compara', (
    tester,
  ) async {
    await _pump(
      tester,
      setUp: (s) {
        s.pastSessions = [_pastWorkout(s)];
        s.historyItems = [_summary('passado-1', 'Peito', records: 1)];
      },
    );
    await _openHistory(tester);

    expect(find.text('Peito'), findsOneWidget);
    expect(find.text('45 min · 4 séries · 3.420 kg'), findsOneWidget);
    expect(
      find.text(
        '$_supino, Tríceps francês, Agachamento livre, Flexão de braços, +1',
      ),
      findsOneWidget,
    );
    expect(find.text('1 recorde'), findsOneWidget);

    await _tap(tester, find.text('Peito'));
    expect(find.bySemanticsLabel('Esforço: 8/10'), findsOneWidget);
    expect(find.text('Bom treino'), findsOneWidget);
    expect(
      find.text('$_supino · Maior carga: 62,5 kg × 8 (antes 60 kg)'),
      findsOneWidget,
    );
    // Séries com o tipo: aquecimento, a válida até a falha e o drop.
    expect(find.bySemanticsLabel('Aquecimento: 20 kg × 15'), findsOneWidget);
    expect(find.bySemanticsLabel('Até a falha: 62,5 kg × 8'), findsOneWidget);
    expect(find.bySemanticsLabel('Drop set: 50 kg × 6'), findsOneWidget);
    // Hoje 500 + 300 = 800 kg; antes 600 + 480 = 1.080 kg.
    expect(
      find.text('Volume: 800 kg (−280 kg que a vez anterior)'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Melhor série: 62,5 kg × 8 · 1RM est. 79,2 kg (antes 60 kg × 10, 80 kg)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('carregar mais busca a próxima página', (tester) async {
    final server = await _pump(
      tester,
      setUp: (s) {
        s.historyPageSize = 1;
        s.historyItems = [
          _summary('t1', 'Treino B'),
          _summary('t2', 'Treino A'),
        ];
      },
    );
    await _openHistory(tester);
    expect(find.text('Treino B'), findsOneWidget);
    expect(find.text('Treino A'), findsNothing);

    await _tap(tester, find.widgetWithText(OutlinedButton, 'Carregar mais'));
    expect(find.text('Treino A'), findsOneWidget);
    expect(server.historyCursors, [null, '1']);
    expect(find.text('Carregar mais'), findsNothing);
  });

  testWidgets('sem treinos nem recordes, os vazios explicam', (tester) async {
    await _pump(tester);
    await _openHistory(tester);
    expect(find.text('Nenhum treino concluído ainda'), findsOneWidget);

    await _tap(tester, find.text('Recordes'));
    expect(find.text('Ainda não há recordes'), findsOneWidget);
  });

  testWidgets('recordes por exercício levam ao histórico do exercício', (
    tester,
  ) async {
    await _pump(
      tester,
      setUp: (s) {
        s.records = [
          {
            'exercise': _ref('ex-supino', _supino),
            'records': [
              _record('max_load', 62.5, reps: 8),
              _record('best_e1rm', 80),
              _record('max_volume', 1080),
            ],
            'last_done_at': '2026-10-30T10:00:00Z',
          },
        ];
        s.exerciseHistories = {
          'ex-supino': {
            'exercise': _ref('ex-supino', _supino),
            'records': [
              _record('max_load', 62.5, reps: 8),
              _record('best_e1rm', 80),
            ],
            'rep_records': [
              _record('rep_max', 62.5, reps: 8),
              _record('rep_max', 60, reps: 10),
            ],
            'sessions': [
              {
                'session_id': 'passado-1',
                'session_name': 'Peito',
                'started_at': '2026-10-30T10:00:00Z',
                'sets': [
                  {
                    'kind': 'working',
                    'reps': 8,
                    'load_kg': 62.5,
                    'duration_s': null,
                    'to_failure': false,
                    'is_segment': false,
                  },
                  {
                    'kind': 'drop',
                    'reps': 6,
                    'load_kg': 50,
                    'duration_s': null,
                    'to_failure': false,
                    'is_segment': true,
                  },
                ],
                'volume_kg': 800,
                'best_e1rm': 79.2,
                'records': ['max_load'],
              },
            ],
            'next_before': null,
          },
        };
      },
    );
    await _openHistory(tester);
    await _tap(tester, find.text('Recordes'));
    expect(find.bySemanticsLabel('Maior carga: 62,5 kg × 8'), findsOneWidget);
    expect(find.bySemanticsLabel('1RM estimado: 80 kg'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Maior volume num treino: 1.080 kg'),
      findsOneWidget,
    );

    await _tap(tester, find.text(_supino));
    expect(find.text('Melhor carga por repetições'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^10 repetições: 60 kg')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Série 1: 62,5 kg × 8'), findsOneWidget);
    expect(find.bySemanticsLabel('Drop set: 50 kg × 6'), findsOneWidget);
    expect(find.text('800 kg · 1RM est. 79,2 kg'), findsOneWidget);
    expect(
      find.textContaining('estimativa (fórmula de Epley)'),
      findsOneWidget,
    );
  });

  testWidgets(
    'o detalhe do exercício abre o histórico; sem registros, explica',
    (tester) async {
      await _pump(tester);
      // O cartão fica mais abaixo no início (lista preguiçosa).
      await tester.scrollUntilVisible(
        find.text('Exercícios'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Exercícios'));
      await _tap(tester, find.text(_supino));
      await _tap(
        tester,
        find.widgetWithText(OutlinedButton, 'Histórico e recordes'),
      );
      expect(find.text('Ainda não há registros'), findsOneWidget);
    },
  );

  testWidgets('o histórico do exercício mostra o 1RM estimado por treino', (
    tester,
  ) async {
    Map<String, Object?> session(String id, String day, double? e1rm) => {
      'session_id': id,
      'session_name': 'Peito',
      'started_at': '${day}T10:00:00Z',
      'sets': <Object>[],
      'volume_kg': 0,
      'best_e1rm': e1rm,
      'records': <String>[],
    };
    await _pump(
      tester,
      setUp: (s) {
        s.records = [
          {
            'exercise': _ref('ex-supino', _supino),
            'records': [_record('best_e1rm', 80)],
            'last_done_at': '2026-10-30T10:00:00Z',
          },
        ];
        s.exerciseHistories = {
          'ex-supino': {
            'exercise': _ref('ex-supino', _supino),
            'records': <Object>[],
            'rep_records': <Object>[],
            // Do mais recente ao mais antigo, como a API devolve.
            'sessions': [
              session('s3', '2026-10-30', 80),
              session('s2', '2026-10-23', null), // sem carga: fica fora
              session('s1', '2026-10-16', 76.5),
            ],
            'next_before': null,
          },
        };
      },
    );
    await _openHistory(tester);
    await _tap(tester, find.text('Recordes'));
    await _tap(tester, find.text(_supino));

    final chart = tester.widget<EvoLineChart>(
      find.byKey(const ValueKey('e1rm-chart')),
    );
    expect([for (final p in chart.points) p.value], [76.5, 80]);
    expect(chart.format(76.5), '76,5 kg');
    expect(find.text('Todos os treinos com carga.'), findsOneWidget);
  });
}
