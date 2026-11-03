import 'package:flutter/foundation.dart';

import '../../training/domain/template.dart';

/// Status de um treino (códigos da API).
abstract final class SessionStatus {
  static const inProgress = 'in_progress';
  static const paused = 'paused';
  static const completed = 'completed';
}

/// Série registrada. Drop e rest-pause são segmentos: apontam para a série que continuam.
@immutable
class LoggedSet {
  const LoggedSet({
    required this.id,
    required this.position,
    required this.kind,
    this.parentSetId,
    this.reps,
    this.loadKg,
    this.durationS,
    this.rir,
    this.rpe,
    this.toFailure = false,
  });

  factory LoggedSet.fromJson(Map<String, dynamic> json) => LoggedSet(
    id: json['id'] as String,
    position: json['position'] as int,
    kind: json['kind'] as String,
    parentSetId: json['parent_set_id'] as String?,
    reps: json['reps'] as int?,
    loadKg: (json['load_kg'] as num?)?.toDouble(),
    durationS: json['duration_s'] as int?,
    rir: json['rir'] as int?,
    rpe: (json['rpe'] as num?)?.toDouble(),
    toFailure: json['to_failure'] as bool? ?? false,
  );

  final String id;
  final int position;
  final String kind;
  final String? parentSetId;
  final int? reps;
  final double? loadKg;
  final int? durationS;
  final int? rir;
  final double? rpe;
  final bool toFailure;

  bool get isWarmup => kind == SetKind.warmup;
  bool get isSegment => parentSetId != null;
}

/// Uma série da última sessão: a referência para preencher a de hoje. As séries
/// principais trazem os próprios segmentos (drop, rest-pause).
@immutable
class PreviousSet {
  const PreviousSet({
    required this.kind,
    this.reps,
    this.loadKg,
    this.durationS,
    this.toFailure = false,
    this.segments = const [],
  });

  factory PreviousSet.fromJson(Map<String, dynamic> json) => PreviousSet(
    kind: json['kind'] as String,
    reps: json['reps'] as int?,
    loadKg: (json['load_kg'] as num?)?.toDouble(),
    durationS: json['duration_s'] as int?,
    toFailure: json['to_failure'] as bool? ?? false,
    segments: (json['segments'] as List<dynamic>? ?? const [])
        .map((s) => PreviousSet.fromJson(s as Map<String, dynamic>))
        .toList(),
  );

  final String kind;
  final int? reps;
  final double? loadKg;
  final int? durationS;
  final bool toFailure;
  final List<PreviousSet> segments;
}

@immutable
class SessionExercise {
  const SessionExercise({
    required this.id,
    required this.exercise,
    required this.position,
    this.group,
    this.plannedSets,
    this.restS,
    this.notes,
    this.sets = const [],
    this.previous = const [],
    this.previousAt,
  });

  factory SessionExercise.fromJson(Map<String, dynamic> json) {
    final previousAt = json['previous_at'] as String?;
    return SessionExercise(
      id: json['id'] as String,
      exercise: TemplateExercise.fromJson(
        json['exercise'] as Map<String, dynamic>,
      ),
      position: json['position'] as int,
      group: json['group'] as int?,
      plannedSets: (json['planned_sets'] as List<dynamic>?)
          ?.map((s) => PlannedSet.fromJson(s as Map<String, dynamic>))
          .toList(),
      restS: json['rest_s'] as int?,
      notes: json['notes'] as String?,
      sets: (json['sets'] as List<dynamic>)
          .map((s) => LoggedSet.fromJson(s as Map<String, dynamic>))
          .toList(),
      previous: (json['previous'] as List<dynamic>? ?? const [])
          .map((s) => PreviousSet.fromJson(s as Map<String, dynamic>))
          .toList(),
      previousAt: previousAt == null ? null : DateTime.parse(previousAt),
    );
  }

  final String id;
  final TemplateExercise exercise;
  final int position;

  /// Índice em [WorkoutSession.groups]; nulo = exercício avulso.
  final int? group;
  final List<PlannedSet>? plannedSets;
  final int? restS;
  final String? notes;
  final List<LoggedSet> sets;
  final List<PreviousSet> previous;
  final DateTime? previousAt;

  SessionExercise withSets(List<LoggedSet> sets) => SessionExercise(
    id: id,
    exercise: exercise,
    position: position,
    group: group,
    plannedSets: plannedSets,
    restS: restS,
    notes: notes,
    sets: sets,
    previous: previous,
    previousAt: previousAt,
  );

  /// Séries principais (sem os segmentos), na ordem.
  List<LoggedSet> get mainSets => [
    for (final s in sets)
      if (!s.isSegment) s,
  ];

  /// Segmentos (drop, rest-pause) da série [parentId], na ordem.
  List<LoggedSet> segmentsOf(String parentId) => [
    for (final s in sets)
      if (s.parentSetId == parentId) s,
  ];
}

/// Treino como devolvido pela API.
@immutable
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.name,
    required this.status,
    required this.startedAt,
    required this.elapsedS,
    required this.receivedAt,
    this.templateId,
    this.groups = const [],
    this.exercises = const [],
    this.setCount = 0,
    this.volumeKg = 0,
  });

  factory WorkoutSession.fromJson(
    Map<String, dynamic> json, {
    DateTime? receivedAt,
  }) => WorkoutSession(
    id: json['id'] as String,
    name: json['name'] as String,
    templateId: json['template_id'] as String?,
    status: json['status'] as String,
    startedAt: DateTime.parse(json['started_at'] as String),
    elapsedS: json['elapsed_s'] as int,
    receivedAt: receivedAt ?? DateTime.now(),
    groups: (json['groups'] as List<dynamic>)
        .map((g) => TemplateGroup.fromJson(g as Map<String, dynamic>))
        .toList(),
    exercises: (json['exercises'] as List<dynamic>)
        .map((e) => SessionExercise.fromJson(e as Map<String, dynamic>))
        .toList(),
    setCount: json['set_count'] as int? ?? 0,
    volumeKg: (json['volume_kg'] as num?)?.toDouble() ?? 0,
  );

  final String id;
  final String name;
  final String? templateId;
  final String status;
  final DateTime startedAt;

  /// Tempo ativo calculado pela API no momento da resposta ([receivedAt]).
  final int elapsedS;
  final DateTime receivedAt;
  final List<TemplateGroup> groups;
  final List<SessionExercise> exercises;
  final int setCount;
  final double volumeKg;

  bool get isPaused => status == SessionStatus.paused;

  /// Séries válidas até agora: as principais, sem aquecimento (um drop set é uma).
  int get liveSetCount => exercises.fold(
    0,
    (sum, e) => sum + e.mainSets.where((s) => !s.isWarmup).length,
  );

  /// Volume até agora: carga × repetições das séries válidas e dos segmentos,
  /// só em exercício com carga externa (como a API calcula no resumo).
  double get liveVolumeKg {
    var total = 0.0;
    for (final e in exercises) {
      if (e.exercise.loadType != 'external') continue;
      for (final s in e.sets) {
        if (!s.isWarmup && s.loadKg != null && s.reps != null) {
          total += s.loadKg! * s.reps!;
        }
      }
    }
    return total;
  }

  /// Tempo ativo agora: o da API mais o que passou desde a resposta (se não pausado).
  /// Não depende do relógio do aparelho bater com o do servidor.
  Duration elapsedAt(DateTime now) {
    final extra = isPaused ? 0 : now.difference(receivedAt).inSeconds;
    return Duration(seconds: elapsedS + (extra < 0 ? 0 : extra));
  }

  /// Descanso depois de uma série do exercício [index]: dentro de um grupo não há
  /// descanso até o último exercício da rodada; aí vale o descanso do grupo.
  int? restAfter(int index) {
    final entry = exercises[index];
    final group = entry.group;
    if (group == null) return entry.restS;
    final isLastOfGroup =
        index == exercises.length - 1 || exercises[index + 1].group != group;
    return isLastOfGroup ? groups[group].restAfterS : null;
  }

  WorkoutSession replaceExercise(int index, SessionExercise entry) =>
      WorkoutSession(
        id: id,
        name: name,
        templateId: templateId,
        status: status,
        startedAt: startedAt,
        elapsedS: elapsedS,
        receivedAt: receivedAt,
        groups: groups,
        exercises: [...exercises]..[index] = entry,
        setCount: setCount,
        volumeKg: volumeKg,
      );
}

/// "48:05" ou "1:02:30".
String formatElapsed(Duration elapsed) {
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes % 60;
  final seconds = elapsed.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}
