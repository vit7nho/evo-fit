import 'package:flutter/foundation.dart';

import '../../profile/domain/profile.dart';

/// Tipos de série planejada (códigos da API).
abstract final class SetKind {
  static const warmup = 'warmup';
  static const working = 'working';
  static const drop = 'drop';
  static const restPause = 'rest_pause';
}

/// Uma série planejada: faixa de repetições ou duração, mais carga e RIR opcionais.
@immutable
class PlannedSet {
  const PlannedSet({
    this.kind = SetKind.working,
    this.repsMin,
    this.repsMax,
    this.durationS,
    this.loadKg,
    this.rirTarget,
  });

  factory PlannedSet.fromJson(Map<String, dynamic> json) => PlannedSet(
    kind: json['kind'] as String? ?? SetKind.working,
    repsMin: json['reps_min'] as int?,
    repsMax: json['reps_max'] as int?,
    durationS: json['duration_s'] as int?,
    loadKg: (json['load_kg'] as num?)?.toDouble(),
    rirTarget: json['rir_target'] as int?,
  );

  final String kind;
  final int? repsMin;
  final int? repsMax;
  final int? durationS;
  final double? loadKg;
  final int? rirTarget;

  bool get isWarmup => kind == SetKind.warmup;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'reps_min': ?repsMin,
    'reps_max': ?repsMax,
    'duration_s': ?durationS,
    'load_kg': ?loadKg,
    'rir_target': ?rirTarget,
  };

  /// "8–12", "10" ou "45 s".
  String get target {
    if (durationS != null) return '$durationS s';
    if (repsMin == null) return '';
    return repsMin == repsMax || repsMax == null
        ? '$repsMin'
        : '$repsMin–$repsMax';
  }
}

/// O exercício como a ficha o descreve (o suficiente para a lista e o editor).
@immutable
class TemplateExercise {
  const TemplateExercise({
    required this.id,
    required this.name,
    required this.equipment,
    required this.loadType,
    this.isActive = true,
    this.primaryMuscles = const [],
  });

  factory TemplateExercise.fromJson(Map<String, dynamic> json) =>
      TemplateExercise(
        id: json['id'] as String,
        name: json['name'] as String,
        equipment: json['equipment'] as String,
        loadType: json['load_type'] as String,
        isActive: json['is_active'] as bool? ?? true,
        primaryMuscles: (json['primary_muscles'] as List<dynamic>? ?? const [])
            .cast<String>(),
      );

  final String id;
  final String name;
  final String equipment;
  final String loadType;
  final bool isActive;
  final List<String> primaryMuscles;

  /// Feito por tempo (prancha): as séries planejam duração, não repetições.
  bool get timed => loadType == 'time';
}

@immutable
class TemplateItem {
  const TemplateItem({
    required this.exercise,
    required this.plannedSets,
    this.restS,
    this.notes,
    this.group,
  });

  factory TemplateItem.fromJson(Map<String, dynamic> json) => TemplateItem(
    exercise: TemplateExercise.fromJson(
      json['exercise'] as Map<String, dynamic>,
    ),
    plannedSets: (json['planned_sets'] as List<dynamic>)
        .map((s) => PlannedSet.fromJson(s as Map<String, dynamic>))
        .toList(),
    restS: json['rest_s'] as int?,
    notes: json['notes'] as String?,
    group: json['group'] as int?,
  );

  final TemplateExercise exercise;
  final List<PlannedSet> plannedSets;
  final int? restS;
  final String? notes;

  /// Índice em [WorkoutTemplate.groups]; nulo = exercício avulso.
  final int? group;
}

@immutable
class TemplateGroup {
  const TemplateGroup({required this.kind, this.restAfterS});

  factory TemplateGroup.fromJson(Map<String, dynamic> json) => TemplateGroup(
    kind: json['kind'] as String,
    restAfterS: json['rest_after_s'] as int?,
  );

  final String kind;
  final int? restAfterS;
}

/// Ficha como devolvida pela API, com o resumo para a lista.
@immutable
class WorkoutTemplate {
  const WorkoutTemplate({
    required this.id,
    required this.name,
    required this.position,
    this.notes,
    this.groups = const [],
    this.items = const [],
    this.exerciseCount = 0,
    this.setCount = 0,
    this.muscles = const [],
  });

  factory WorkoutTemplate.fromJson(Map<String, dynamic> json) =>
      WorkoutTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        notes: json['notes'] as String?,
        position: json['position'] as int,
        groups: (json['groups'] as List<dynamic>)
            .map((g) => TemplateGroup.fromJson(g as Map<String, dynamic>))
            .toList(),
        items: (json['items'] as List<dynamic>)
            .map((i) => TemplateItem.fromJson(i as Map<String, dynamic>))
            .toList(),
        exerciseCount: json['exercise_count'] as int? ?? 0,
        setCount: json['set_count'] as int? ?? 0,
        muscles: (json['muscles'] as List<dynamic>? ?? const []).cast<String>(),
      );

  final String id;
  final String name;
  final String? notes;
  final int position;
  final List<TemplateGroup> groups;
  final List<TemplateItem> items;
  final int exerciseCount;
  final int setCount;

  /// Músculos principais trabalhados (ids estáveis, na ordem do catálogo).
  final List<String> muscles;
}

@immutable
class GroupKind {
  const GroupKind(this.code, this.label, this.minSize, this.maxSize);

  final String code;
  final String label;
  final int minSize;
  final int maxSize;
}

/// Vocabulários das fichas (GET /workout-options).
@immutable
class WorkoutOptions {
  const WorkoutOptions({required this.groupKinds, required this.setKinds});

  factory WorkoutOptions.fromJson(Map<String, dynamic> json) => WorkoutOptions(
    groupKinds: [
      for (final k in json['group_kinds'] as List<dynamic>)
        GroupKind(
          (k as Map<String, dynamic>)['code'] as String,
          k['label'] as String,
          k['min_size'] as int,
          k['max_size'] as int,
        ),
    ],
    setKinds: (json['set_kinds'] as List<dynamic>)
        .map((o) => Option.fromJson(o as Map<String, dynamic>))
        .toList(),
  );

  final List<GroupKind> groupKinds;
  final List<Option> setKinds;

  String groupLabel(String code) => groupKinds
      .firstWhere(
        (k) => k.code == code,
        orElse: () => GroupKind(code, code, 0, 0),
      )
      .label;

  String setKindLabel(String code) => ProfileOptions.labelOf(setKinds, code);
}
