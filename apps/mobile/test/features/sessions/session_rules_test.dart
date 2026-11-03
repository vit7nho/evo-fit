import 'package:evofit/features/sessions/domain/session.dart';
import 'package:evofit/features/sessions/domain/set_rows.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _exercise(
  String id, {
  int? group,
  int? rest = 90,
  List<Map<String, Object?>>? planned,
  List<Map<String, Object?>> sets = const [],
  List<Map<String, Object?>> previous = const [],
  bool timed = false,
}) => {
  'id': id,
  'exercise': {
    'id': 'ex-$id',
    'name': id,
    'equipment': 'barbell',
    'load_type': timed ? 'time' : 'external',
    'is_active': true,
    'primary_muscles': ['chest'],
  },
  'position': 0,
  'group': group,
  'planned_sets': planned,
  'rest_s': rest,
  'notes': null,
  'sets': sets,
  'previous': previous,
  'previous_at': previous.isEmpty ? null : '2026-10-30T10:00:00Z',
};

Map<String, Object?> _set(
  int position, {
  int reps = 10,
  double load = 60,
  String kind = 'working',
  String? parent,
}) => {
  'id': 's$position',
  'position': position,
  'kind': kind,
  'parent_set_id': parent,
  'reps': reps,
  'load_kg': load,
  'duration_s': null,
  'rir': null,
  'rpe': null,
  'to_failure': false,
  'completed_at': '2026-11-01T10:00:00Z',
};

WorkoutSession _session(
  List<Map<String, Object?>> exercises, {
  List<Map<String, Object?>> groups = const [],
  String status = 'in_progress',
  int elapsed = 600,
  DateTime? receivedAt,
}) => WorkoutSession.fromJson({
  'id': 'treino',
  'name': 'Treino A',
  'template_id': null,
  'status': status,
  'started_at': '2026-11-01T10:00:00Z',
  'paused_at': null,
  'paused_total_s': 0,
  'ended_at': null,
  'elapsed_s': elapsed,
  'perceived_effort': null,
  'notes': null,
  'groups': groups,
  'exercises': exercises,
  'set_count': 0,
  'volume_kg': 0,
}, receivedAt: receivedAt);

void main() {
  group('descanso', () {
    final session = _session(
      [
        _exercise('supino', rest: 120),
        _exercise('crucifixo', group: 0),
        _exercise('triceps', group: 0),
        _exercise('livre', rest: null),
      ],
      groups: [
        {'id': 'g', 'kind': 'biset', 'rest_after_s': 75},
      ],
    );

    test('exercício avulso descansa o próprio tempo', () {
      expect(session.restAfter(0), 120);
      expect(session.restAfter(3), isNull);
    });

    test('dentro do bi-set não há descanso; no fim da rodada, o do grupo', () {
      expect(session.restAfter(1), isNull);
      expect(session.restAfter(2), 75);
    });
  });

  group('linhas da tabela', () {
    List<SetRowDraft> rowsOf(SessionExercise entry) {
      var next = 0;
      return buildRows(entry, () => next++);
    }

    /// Sugestão da linha [i] sem nada digitado (linhas feitas valem o salvo).
    RowSuggestion suggest(SessionExercise e, List<SetRowDraft> rows, int i) =>
        suggestRow(
          e,
          rows,
          i,
          valuesOf: (j) {
            final logged = e.sets.where((s) => s.id == rows[j].loggedId);
            if (logged.isEmpty) return suggest(e, rows, j);
            final s = logged.single;
            return (reps: s.reps, loadKg: s.loadKg, durationS: s.durationS);
          },
        );

    SessionExercise entryOf(Map<String, Object?> json) =>
        SessionExercise.fromJson(json);

    test('o plano define as linhas; tudo feito ganha uma linha em branco', () {
      final planned = [
        for (var i = 0; i < 3; i++)
          {'kind': 'working', 'reps_min': 8, 'reps_max': 12},
      ];
      final fresh = rowsOf(entryOf(_exercise('a', planned: planned)));
      expect(fresh.map((r) => (r.kind, r.isDone)), [
        for (var i = 0; i < 3; i++) (RowKind.working, false),
      ]);

      final done = rowsOf(
        entryOf(
          _exercise(
            'a',
            planned: planned,
            sets: [for (var i = 0; i < 4; i++) _set(i)],
          ),
        ),
      );
      expect(done.where((r) => r.isDone), hasLength(4));
      expect(done.last.isDone, isFalse);
    });

    test('sem plano, uma linha em branco', () {
      expect(rowsOf(entryOf(_exercise('a'))), hasLength(1));
      expect(rowsOf(entryOf(_exercise('a', sets: [_set(0)]))), hasLength(2));
    });

    test(
      'drop e rest-pause do plano viram série válida + linha do segmento',
      () {
        final rows = rowsOf(
          entryOf(
            _exercise(
              'a',
              planned: [
                {'kind': 'drop', 'reps_min': 8},
                {'kind': 'rest_pause', 'reps_min': 8},
                {'kind': 'warmup', 'reps_min': 15},
              ],
            ),
          ),
        );
        expect(rows.map((r) => r.kind), [
          RowKind.working,
          RowKind.drop,
          RowKind.working,
          RowKind.restPause,
          RowKind.warmup,
        ]);
      },
    );

    test(
      'séries feitas: cada principal seguida dos segmentos; falha vira F',
      () {
        final entry = entryOf(
          _exercise(
            'a',
            sets: [
              {..._set(0), 'to_failure': true},
              _set(1),
              _set(2, kind: 'drop', parent: 's0', load: 47.5),
            ],
          ),
        );
        final rows = rowsOf(entry);
        expect(rows.map((r) => (r.kind, r.loggedId)).take(3), [
          (RowKind.failure, 's0'),
          (RowKind.drop, 's2'),
          (RowKind.working, 's1'),
        ]);
      },
    );

    test('o número conta só as válidas; letras para os outros tipos', () {
      final rows = [
        for (final (i, k) in [
          RowKind.warmup,
          RowKind.working,
          RowKind.drop,
          RowKind.failure,
          RowKind.working,
        ].indexed)
          SetRowDraft(id: i, kind: k),
      ];
      expect(
        [for (var i = 0; i < rows.length; i++) rowBadge(rows, i)],
        ['A', '1', 'D', 'F', '3'],
      );
      // O segmento continua a principal mais próxima acima.
      expect(parentRowOf(rows, 2), 1);
      expect(parentRowOf(rows, 0), isNull);
    });

    test('falha vai para a API como válida com to_failure', () {
      expect(RowKind.failure.apiFields, {
        'kind': 'working',
        'to_failure': true,
      });
      expect(RowKind.fromSet('working', toFailure: true), RowKind.failure);
      expect(RowKind.fromSet('rest_pause'), RowKind.restPause);
    });

    test(
      'sugestão: última vez na mesma linha, depois o plano, depois a de cima',
      () {
        final entry = entryOf(
          _exercise(
            'a',
            planned: [
              {'kind': 'warmup', 'reps_min': 15, 'reps_max': 15},
              {'kind': 'working', 'reps_min': 8, 'reps_max': 12, 'load_kg': 50},
              {'kind': 'working', 'reps_min': 8, 'reps_max': 12},
            ],
            previous: [
              {'kind': 'warmup', 'reps': 15, 'load_kg': 20, 'duration_s': null},
              {
                'kind': 'working',
                'reps': 10,
                'load_kg': 60,
                'duration_s': null,
              },
            ],
          ),
        );
        final rows = rowsOf(entry);
        expect(suggest(entry, rows, 0), (
          reps: 15,
          loadKg: 20.0,
          durationS: null,
        ));
        expect(suggest(entry, rows, 1), (
          reps: 10,
          loadKg: 60.0,
          durationS: null,
        ));
        // Sem última vez na linha: o plano (mínimo da faixa) e a carga da de cima.
        expect(suggest(entry, rows, 2), (
          reps: 8,
          loadKg: 60.0,
          durationS: null,
        ));
      },
    );

    test('exercício por tempo sugere a duração', () {
      final entry = entryOf(
        _exercise(
          'prancha',
          timed: true,
          previous: [
            {
              'kind': 'working',
              'reps': null,
              'load_kg': null,
              'duration_s': 45,
            },
          ],
        ),
      );
      expect(suggest(entry, rowsOf(entry), 0).durationS, 45);
    });

    test(
      'drop tira 20% da linha de cima (múltiplo de 2,5); rest-pause repete',
      () {
        RowSuggestion segment(double load, RowKind kind) {
          final entry = entryOf(_exercise('a', sets: [_set(0, load: load)]));
          final rows = [
            SetRowDraft(id: 0, kind: RowKind.working, loggedId: 's0'),
            SetRowDraft(id: 1, kind: kind),
          ];
          return suggest(entry, rows, 1);
        }

        expect(segment(60, RowKind.drop).loadKg, 47.5);
        expect(segment(60, RowKind.drop).reps, isNull);
        expect(segment(60, RowKind.restPause).loadKg, 60);
        // Carga pequena: tira ao menos 2,5 kg e nunca fica zerada.
        expect(segment(10, RowKind.drop).loadKg, 7.5);
        expect(segment(5, RowKind.drop).loadKg, 2.5);
        expect(segment(2.5, RowKind.drop).loadKg, isNull);
      },
    );

    test('o drop da última vez fica na linha dele e vale mais que os 20%', () {
      final entry = entryOf(
        _exercise(
          'a',
          sets: [_set(0, load: 60)],
          previous: [
            {
              'kind': 'working',
              'reps': 10,
              'load_kg': 60,
              'duration_s': null,
              'to_failure': true,
              'segments': [
                {'kind': 'drop', 'reps': 6, 'load_kg': 40, 'duration_s': null},
              ],
            },
          ],
        ),
      );
      expect(previousAt(entry, 1)?.kind, 'drop');
      final rows = [
        SetRowDraft(id: 0, kind: RowKind.working, loggedId: 's0'),
        SetRowDraft(id: 1, kind: RowKind.drop),
      ];
      expect(suggest(entry, rows, 1), (reps: 6, loadKg: 40.0, durationS: null));
    });

    test('acerto com o servidor: série que sumiu volta a ficar por fazer', () {
      final entry = entryOf(_exercise('a', sets: [_set(1)]));
      var next = 10;
      final rows = reconcileRows(
        [
          SetRowDraft(id: 0, kind: RowKind.working, loggedId: 's0'),
          SetRowDraft(id: 1, kind: RowKind.working),
        ],
        entry,
        () => next++,
      );
      expect(rows.map((r) => (r.id, r.loggedId)), [
        (0, null),
        (1, null),
        (10, 's1'),
      ]);
    });

    test('resumo ao vivo: séries válidas e volume com os segmentos', () {
      final session = _session([
        _exercise(
          'a',
          sets: [
            _set(0, load: 20, reps: 15, kind: 'warmup'),
            _set(1, load: 60, reps: 10),
            _set(2, kind: 'drop', parent: 's1', load: 45, reps: 6),
          ],
        ),
      ]);
      expect(session.liveSetCount, 1);
      expect(session.liveVolumeKg, 60 * 10 + 45 * 6);
    });
  });

  group('tempo de treino', () {
    test(
      'soma o tempo local desde a resposta, sem depender do relógio da API',
      () {
        final received = DateTime(2026, 11, 1, 10, 30);
        final session = _session([], elapsed: 600, receivedAt: received);

        final later = received.add(const Duration(seconds: 65));
        expect(session.elapsedAt(later), const Duration(seconds: 665));
        expect(formatElapsed(session.elapsedAt(later)), '11:05');
      },
    );

    test('pausado, o tempo para', () {
      final received = DateTime(2026, 11, 1, 10, 30);
      final session = _session(
        [],
        status: 'paused',
        elapsed: 600,
        receivedAt: received,
      );
      expect(
        session.elapsedAt(received.add(const Duration(minutes: 5))),
        const Duration(seconds: 600),
      );
    });

    test('formato com horas', () {
      expect(
        formatElapsed(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });
  });
}
