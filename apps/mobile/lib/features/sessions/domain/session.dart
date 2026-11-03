import 'package:flutter/foundation.dart';

import '../../training/domain/template.dart';

/// Status de um treino (códigos da API).
abstract final class SessionStatus {
  static const inProgress = 'in_progress';
  static const paused = 'paused';
  static const completed = 'completed';
}

/// Técnicas que continuam uma série válida, registradas como segmentos dela.
const segmentKinds = {SetKind.drop, SetKind.restPause};

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

/// Valores sugeridos para uma linha ainda não feita.
@immutable
class SetSuggestion {
  const SetSuggestion({
    this.kind = SetKind.working,
    this.reps,
    this.loadKg,
    this.durationS,
  });

  final String kind;
  final int? reps;
  final double? loadKg;
  final int? durationS;
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

  /// Séries principais (sem os segmentos), na ordem: uma por linha da tela.
  List<LoggedSet> get mainSets => [
    for (final s in sets)
      if (!s.isSegment) s,
  ];

  /// Segmentos (drop, rest-pause) da série [parentId], na ordem.
  List<LoggedSet> segmentsOf(String parentId) => [
    for (final s in sets)
      if (s.parentSetId == parentId) s,
  ];

  /// Quantas linhas mostrar: o plano, o que já foi feito e as acrescentadas na hora.
  /// Sem plano (exercício avulso), sempre sobra uma linha em branco para a próxima.
  int rowCount({int extra = 0}) {
    final done = mainSets.length;
    final planned = plannedSets?.length ?? 0;
    final base = planned == 0 ? done + 1 : planned;
    final count = base > done ? base : done;
    return count + extra;
  }

  /// Técnica que o plano marca para a linha [row] (drop ou rest-pause), se houver.
  String? technique(int row) {
    final planned = plannedSets != null && row < plannedSets!.length
        ? plannedSets![row].kind
        : null;
    return segmentKinds.contains(planned) ? planned : null;
  }

  /// Sugestão para a linha [row]: a série de mesma posição na última sessão e, na
  /// falta dela, o plano da ficha (o mínimo da faixa de repetições). Uma série
  /// planejada como drop ou rest-pause é feita como válida; os segmentos vêm depois.
  SetSuggestion suggestion(int row) {
    final planned = plannedSets != null && row < plannedSets!.length
        ? plannedSets![row]
        : null;
    final last = row < previous.length ? previous[row] : null;
    final done = mainSets;
    final fallback = done.isNotEmpty ? done.last : null;
    final plannedKind = planned == null || segmentKinds.contains(planned.kind)
        ? null
        : planned.kind;
    return SetSuggestion(
      kind: plannedKind ?? last?.kind ?? SetKind.working,
      reps: last?.reps ?? planned?.repsMin ?? fallback?.reps,
      loadKg: last?.loadKg ?? planned?.loadKg ?? fallback?.loadKg,
      durationS: last?.durationS ?? planned?.durationS ?? fallback?.durationS,
    );
  }

  /// Sugestão para o próximo segmento [kind] da série [parent] (linha [row]): o
  /// segmento de mesma posição da última vez; sem ele, o drop tira 20% da carga
  /// anterior (múltiplo de 2,5 kg) e o rest-pause repete a carga.
  SetSuggestion segmentSuggestion(int row, LoggedSet parent, String kind) {
    final done = segmentsOf(parent.id);
    final last = row < previous.length ? previous[row] : null;
    final before = last == null
        ? const <PreviousSet>[]
        : last.segments.where((s) => s.kind == kind).toList();
    final index = done.where((s) => s.kind == kind).length;
    final match = index < before.length ? before[index] : null;
    final lastLoad = done.isNotEmpty ? done.last.loadKg : parent.loadKg;
    double? load = lastLoad;
    if (kind == SetKind.drop && lastLoad != null) {
      final dropped = (lastLoad * 0.8 / 2.5).round() * 2.5;
      load = dropped < lastLoad ? dropped : lastLoad - 2.5;
      if (load <= 0) load = null;
    }
    return SetSuggestion(
      kind: kind,
      reps: match?.reps,
      loadKg: match?.loadKg ?? load,
    );
  }
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
