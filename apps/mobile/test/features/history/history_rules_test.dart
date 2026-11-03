import 'package:evofit/features/history/domain/history.dart';
import 'package:evofit/features/sessions/domain/session.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _set(
  String id, {
  String kind = 'working',
  int reps = 10,
  double load = 60,
  String? parent,
}) => {
  'id': id,
  'position': 0,
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

SessionExercise _entry({
  String loadType = 'external',
  List<Map<String, Object?>> sets = const [],
  List<Map<String, Object?>> previous = const [],
}) => SessionExercise.fromJson({
  'id': 'e',
  'exercise': {
    'id': 'ex',
    'name': 'Supino',
    'equipment': 'barbell',
    'load_type': loadType,
    'is_active': true,
    'primary_muscles': ['chest'],
  },
  'position': 0,
  'group': null,
  'planned_sets': null,
  'rest_s': 90,
  'notes': null,
  'sets': sets,
  'previous': previous,
  'previous_at': null,
});

void main() {
  test('volume com separador de milhar, arredondado', () {
    expect(formatVolume(0), '0');
    expect(formatVolume(999.6), '1.000');
    expect(formatVolume(123456), '123.456');
  });

  test('1RM estimado igual ao da API (Epley, de 1 a 12 repetições)', () {
    expect(estimate1rm(100, 1), 100);
    expect(estimate1rm(100, 10), 133.3);
    expect(estimate1rm(62.5, 8), 79.2);
    expect(estimate1rm(100, 13), isNull);
    expect(estimate1rm(null, 5), isNull);
  });

  test('texto de cada tipo de recorde', () {
    expect(recordValue(RecordKind.maxLoad, 62.5, reps: 8), '62,5 kg × 8');
    expect(recordValue(RecordKind.bestE1rm, 80), '80 kg');
    expect(recordValue(RecordKind.maxVolume, 1080), '1.080 kg');
    expect(recordValue(RecordKind.maxReps, 25), '25 repetições');
    expect(recordValue(RecordKind.maxDuration, 60), '60 s');
  });

  test('comparação: volume com segmentos e melhor série pelo 1RM estimado', () {
    final c = compareWithPrevious(
      _entry(
        sets: [
          _set('w', kind: 'warmup', reps: 15, load: 20),
          _set('a', reps: 8, load: 62.5),
          _set('d', kind: 'drop', reps: 6, load: 50, parent: 'a'),
        ],
        previous: [
          {'kind': 'working', 'reps': 10, 'load_kg': 60, 'duration_s': null},
          {'kind': 'working', 'reps': 8, 'load_kg': 60, 'duration_s': null},
        ],
      ),
    );
    expect((c.volumeKg, c.previousVolumeKg, c.volumeDelta), (800, 1080, -280));
    expect(c.best, (loadKg: 62.5, reps: 8, e1rm: 79.2));
    expect(c.previousBest, (loadKg: 60.0, reps: 10, e1rm: 80.0));
  });

  test('sem vez anterior, só o de hoje; sem carga externa, sem comparação', () {
    final first = compareWithPrevious(_entry(sets: [_set('a')]));
    expect(
      (first.volumeKg, first.previousVolumeKg, first.volumeDelta),
      (600, null, null),
    );
    final body = compareWithPrevious(
      _entry(loadType: 'bodyweight', sets: [_set('a')]),
    );
    expect((body.volumeKg, body.best), (null, null));
  });
}
