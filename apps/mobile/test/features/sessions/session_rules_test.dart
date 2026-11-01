import 'package:evofit/features/sessions/domain/session.dart';
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

Map<String, Object?> _set(int position, {int reps = 10, double load = 60}) => {
  'id': 's$position',
  'position': position,
  'kind': 'working',
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

  group('linhas e sugestões', () {
    test('o plano define as linhas; o que passar dele aparece também', () {
      final planned = [
        for (var i = 0; i < 3; i++)
          {'kind': 'working', 'reps_min': 8, 'reps_max': 12},
      ];
      final entry = SessionExercise.fromJson(_exercise('a', planned: planned));
      expect(entry.rowCount(), 3);
      expect(entry.rowCount(extra: 1), 4);

      final done = SessionExercise.fromJson(
        _exercise(
          'a',
          planned: planned,
          sets: [for (var i = 0; i < 4; i++) _set(i)],
        ),
      );
      expect(done.rowCount(), 4);
    });

    test('sem plano, sempre sobra uma linha em branco', () {
      final entry = SessionExercise.fromJson(_exercise('a'));
      expect(entry.rowCount(), 1);
      final after = SessionExercise.fromJson(_exercise('a', sets: [_set(0)]));
      expect(after.rowCount(), 2);
    });

    test('a sugestão vem da última sessão, depois do plano', () {
      final entry = SessionExercise.fromJson(
        _exercise(
          'a',
          planned: [
            {'kind': 'warmup', 'reps_min': 15, 'reps_max': 15},
            {'kind': 'working', 'reps_min': 8, 'reps_max': 12, 'load_kg': 50},
            {'kind': 'working', 'reps_min': 8, 'reps_max': 12},
          ],
          previous: [
            {'kind': 'warmup', 'reps': 15, 'load_kg': 20, 'duration_s': null},
            {'kind': 'working', 'reps': 10, 'load_kg': 60, 'duration_s': null},
          ],
        ),
      );

      final warmup = entry.suggestion(0);
      expect((warmup.kind, warmup.reps, warmup.loadKg), ('warmup', 15, 20.0));
      final second = entry.suggestion(1);
      expect((second.kind, second.reps, second.loadKg), ('working', 10, 60.0));
      // Sem série anterior nessa posição: o plano (mínimo da faixa).
      final third = entry.suggestion(2);
      expect((third.reps, third.loadKg), (8, null));
    });

    test('sem plano nem histórico, repete a última série de hoje', () {
      final entry = SessionExercise.fromJson(
        _exercise('a', sets: [_set(0, reps: 12, load: 40)]),
      );
      final next = entry.suggestion(1);
      expect((next.reps, next.loadKg), (12, 40.0));
    });

    test('exercício por tempo sugere a duração', () {
      final entry = SessionExercise.fromJson(
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
      expect(entry.suggestion(0).durationS, 45);
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
