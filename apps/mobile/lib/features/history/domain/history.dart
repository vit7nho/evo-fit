import 'package:flutter/foundation.dart';

import '../../goals/presentation/goal_format.dart';
import '../../sessions/domain/session.dart';
import '../../training/domain/template.dart';

/// Tipos de recorde (códigos da API) e como mostrar cada um.
abstract final class RecordKind {
  static const maxLoad = 'max_load';
  static const bestE1rm = 'best_e1rm';
  static const maxVolume = 'max_volume';
  static const maxReps = 'max_reps';
  static const maxDuration = 'max_duration';
  static const repMax = 'rep_max';

  static String label(String kind) => switch (kind) {
    maxLoad => 'Maior carga',
    bestE1rm => '1RM estimado',
    maxVolume => 'Maior volume num treino',
    maxReps => 'Mais repetições',
    maxDuration => 'Maior tempo',
    _ => 'Recorde',
  };
}

/// Um recorde pessoal: o melhor valor até agora e onde aconteceu.
@immutable
class PersonalRecord {
  const PersonalRecord({
    required this.kind,
    required this.value,
    required this.sessionId,
    required this.achievedAt,
    this.reps,
    this.loadKg,
  });

  factory PersonalRecord.fromJson(Map<String, dynamic> json) => PersonalRecord(
    kind: json['kind'] as String,
    value: (json['value'] as num).toDouble(),
    reps: json['reps'] as int?,
    loadKg: (json['load_kg'] as num?)?.toDouble(),
    sessionId: json['session_id'] as String,
    achievedAt: DateTime.parse(json['achieved_at'] as String).toLocal(),
  );

  final String kind;
  final double value;
  final int? reps;
  final double? loadKg;
  final String sessionId;
  final DateTime achievedAt;

  /// "62,5 kg × 8", "80 kg", "1.080 kg", "25 repetições", "60 s".
  String get display => recordValue(kind, value, reps: reps, loadKg: loadKg);
}

/// Recorde batido num treino: o novo valor e o anterior.
@immutable
class RecordEvent {
  const RecordEvent({
    required this.exerciseId,
    required this.kind,
    required this.value,
    required this.previous,
    this.reps,
    this.loadKg,
  });

  factory RecordEvent.fromJson(Map<String, dynamic> json) => RecordEvent(
    exerciseId: json['exercise_id'] as String,
    kind: json['kind'] as String,
    value: (json['value'] as num).toDouble(),
    reps: json['reps'] as int?,
    loadKg: (json['load_kg'] as num?)?.toDouble(),
    previous: (json['previous'] as num).toDouble(),
  );

  final String exerciseId;
  final String kind;
  final double value;
  final int? reps;
  final double? loadKg;
  final double previous;

  String get display => recordValue(kind, value, reps: reps, loadKg: loadKg);
  String get previousDisplay => recordValue(kind, previous);
}

/// Texto do valor de um recorde.
String recordValue(String kind, double value, {int? reps, double? loadKg}) =>
    switch (kind) {
      RecordKind.maxLoad || RecordKind.repMax when reps != null =>
        '${formatDecimal(value)} kg × $reps',
      RecordKind.maxVolume => '${formatVolume(value)} kg',
      RecordKind.maxReps =>
        value == 1 ? '1 repetição' : '${value.round()} repetições',
      RecordKind.maxDuration => '${value.round()} s',
      _ => '${formatDecimal(value)} kg',
    };

/// Volume arredondado, com separador de milhar: "3.420".
String formatVolume(double kg) {
  final digits = kg.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 1RM estimado (Epley), como na API: só de 1 a 12 repetições.
double? estimate1rm(double? loadKg, int? reps) {
  if (loadKg == null || loadKg <= 0 || reps == null || reps < 1 || reps > 12) {
    return null;
  }
  final value = reps == 1 ? loadKg : loadKg * (1 + reps / 30);
  return (value * 10).round() / 10;
}

/// Um treino concluído, como aparece na lista do histórico.
@immutable
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.setCount,
    required this.volumeKg,
    required this.exerciseCount,
    required this.exerciseNames,
    required this.recordCount,
    this.durationS,
  });

  factory SessionSummary.fromJson(Map<String, dynamic> json) => SessionSummary(
    id: json['id'] as String,
    name: json['name'] as String,
    startedAt: DateTime.parse(json['started_at'] as String).toLocal(),
    durationS: json['duration_s'] as int?,
    setCount: json['set_count'] as int,
    volumeKg: (json['volume_kg'] as num).toDouble(),
    exerciseCount: json['exercise_count'] as int,
    exerciseNames: (json['exercise_names'] as List<dynamic>).cast<String>(),
    recordCount: json['record_count'] as int,
  );

  final String id;
  final String name;
  final DateTime startedAt;
  final int? durationS;
  final int setCount;
  final double volumeKg;
  final int exerciseCount;
  final List<String> exerciseNames;
  final int recordCount;
}

/// Uma página de resultados e o cursor da próxima (nulo quando acabou).
@immutable
class Paged<T> {
  const Paged(this.items, this.nextBefore);

  final List<T> items;
  final String? nextBefore;
}

/// Série do histórico (os segmentos vêm logo depois da série principal).
@immutable
class HistorySet {
  const HistorySet({
    required this.kind,
    required this.toFailure,
    required this.isSegment,
    this.reps,
    this.loadKg,
    this.durationS,
  });

  factory HistorySet.fromJson(Map<String, dynamic> json) => HistorySet(
    kind: json['kind'] as String,
    reps: json['reps'] as int?,
    loadKg: (json['load_kg'] as num?)?.toDouble(),
    durationS: json['duration_s'] as int?,
    toFailure: json['to_failure'] as bool,
    isSegment: json['is_segment'] as bool,
  );

  final String kind;
  final int? reps;
  final double? loadKg;
  final int? durationS;
  final bool toFailure;
  final bool isSegment;
}

/// As séries de um exercício num treino.
@immutable
class ExerciseSession {
  const ExerciseSession({
    required this.sessionId,
    required this.sessionName,
    required this.startedAt,
    required this.sets,
    required this.volumeKg,
    required this.records,
    this.bestE1rm,
  });

  factory ExerciseSession.fromJson(Map<String, dynamic> json) =>
      ExerciseSession(
        sessionId: json['session_id'] as String,
        sessionName: json['session_name'] as String,
        startedAt: DateTime.parse(json['started_at'] as String).toLocal(),
        sets: (json['sets'] as List<dynamic>)
            .map((s) => HistorySet.fromJson(s as Map<String, dynamic>))
            .toList(),
        volumeKg: (json['volume_kg'] as num).toDouble(),
        bestE1rm: (json['best_e1rm'] as num?)?.toDouble(),
        records: (json['records'] as List<dynamic>).cast<String>(),
      );

  final String sessionId;
  final String sessionName;
  final DateTime startedAt;
  final List<HistorySet> sets;
  final double volumeKg;
  final double? bestE1rm;
  final List<String> records;
}

/// Histórico de um exercício: recordes e as vezes em que foi feito.
@immutable
class ExerciseHistory {
  const ExerciseHistory({
    required this.exercise,
    required this.records,
    required this.repRecords,
    required this.sessions,
    this.nextBefore,
  });

  factory ExerciseHistory.fromJson(Map<String, dynamic> json) =>
      ExerciseHistory(
        exercise: TemplateExercise.fromJson(
          json['exercise'] as Map<String, dynamic>,
        ),
        records: _records(json['records']),
        repRecords: _records(json['rep_records']),
        sessions: (json['sessions'] as List<dynamic>)
            .map((s) => ExerciseSession.fromJson(s as Map<String, dynamic>))
            .toList(),
        nextBefore: json['next_before'] as String?,
      );

  final TemplateExercise exercise;
  final List<PersonalRecord> records;
  final List<PersonalRecord> repRecords;
  final List<ExerciseSession> sessions;
  final String? nextBefore;

  /// Mais uma página de treinos, mantendo os recordes.
  ExerciseHistory append(ExerciseHistory next) => ExerciseHistory(
    exercise: exercise,
    records: records,
    repRecords: repRecords,
    sessions: [...sessions, ...next.sessions],
    nextBefore: next.nextBefore,
  );
}

/// Recordes de um exercício, para a lista geral.
@immutable
class ExerciseRecords {
  const ExerciseRecords({
    required this.exercise,
    required this.records,
    required this.lastDoneAt,
  });

  factory ExerciseRecords.fromJson(Map<String, dynamic> json) =>
      ExerciseRecords(
        exercise: TemplateExercise.fromJson(
          json['exercise'] as Map<String, dynamic>,
        ),
        records: _records(json['records']),
        lastDoneAt: DateTime.parse(json['last_done_at'] as String).toLocal(),
      );

  final TemplateExercise exercise;
  final List<PersonalRecord> records;
  final DateTime lastDoneAt;
}

List<PersonalRecord> _records(Object? json) => (json as List<dynamic>)
    .map((r) => PersonalRecord.fromJson(r as Map<String, dynamic>))
    .toList();

/// Comparação de um exercício com a vez anterior: volume e melhor série.
@immutable
class ExerciseComparison {
  const ExerciseComparison({
    this.volumeKg,
    this.previousVolumeKg,
    this.best,
    this.previousBest,
  });

  final double? volumeKg;
  final double? previousVolumeKg;

  /// Melhor série (maior 1RM estimado) de hoje e da vez anterior.
  final ({double loadKg, int reps, double e1rm})? best;
  final ({double loadKg, int reps, double e1rm})? previousBest;

  double? get volumeDelta => volumeKg == null || previousVolumeKg == null
      ? null
      : volumeKg! - previousVolumeKg!;
}

typedef _Set = ({String kind, double? load, int? reps, bool segment});

/// Compara as séries do exercício neste treino com as da vez anterior
/// ([SessionExercise.previous]). Só faz sentido com carga externa.
ExerciseComparison compareWithPrevious(SessionExercise entry) {
  if (entry.exercise.loadType != 'external') return const ExerciseComparison();
  ({double loadKg, int reps, double e1rm})? bestOf(Iterable<_Set> sets) {
    ({double loadKg, int reps, double e1rm})? best;
    for (final s in sets) {
      if (s.kind != SetKind.working || s.segment) continue;
      final estimate = estimate1rm(s.load, s.reps);
      if (estimate != null && (best == null || estimate > best.e1rm)) {
        best = (loadKg: s.load!, reps: s.reps!, e1rm: estimate);
      }
    }
    return best;
  }

  double volumeOf(Iterable<_Set> sets) => sets
      .where(
        (s) => s.kind != SetKind.warmup && s.load != null && s.reps != null,
      )
      .fold(0, (sum, s) => sum + s.load! * s.reps!);

  final today = <_Set>[
    for (final s in entry.sets)
      (kind: s.kind, load: s.loadKg, reps: s.reps, segment: s.isSegment),
  ];
  final before = <_Set>[
    for (final p in entry.previous) ...[
      (kind: p.kind, load: p.loadKg, reps: p.reps, segment: false),
      for (final g in p.segments)
        (kind: g.kind, load: g.loadKg, reps: g.reps, segment: true),
    ],
  ];
  return ExerciseComparison(
    volumeKg: today.isEmpty ? null : volumeOf(today),
    previousVolumeKg: before.isEmpty ? null : volumeOf(before),
    best: bestOf(today),
    previousBest: bestOf(before),
  );
}
