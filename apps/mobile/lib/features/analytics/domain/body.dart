import 'package:flutter/foundation.dart';

import '../../goals/presentation/goal_format.dart';

/// Faixa de estímulo calculada pela API (metodologia versionada, DATA_MODEL §6).
enum StimulusBand {
  none('Sem estímulo'),
  low('Baixo'),
  mid('Moderado'),
  high('Alto');

  const StimulusBand(this.label);

  final String label;

  static StimulusBand parse(String code) => StimulusBand.values.firstWhere(
    (band) => band.name == code,
    orElse: () => StimulusBand.none,
  );
}

/// Lado do corpo onde o músculo aparece no mapa (`both`: nos dois).
enum BodyView {
  front('Frente'),
  back('Costas');

  const BodyView(this.label);

  final String label;
}

@immutable
class MuscleStimulus {
  const MuscleStimulus({
    required this.muscleId,
    required this.name,
    required this.view,
    required this.weightedSets,
    required this.weightedSetsPerWeek,
    required this.band,
    required this.frequency,
    required this.volumeLoadKg,
  });

  factory MuscleStimulus.fromJson(Map<String, dynamic> json) => MuscleStimulus(
    muscleId: json['muscle_id'] as String,
    name: json['name'] as String,
    view: json['view'] as String,
    weightedSets: (json['weighted_sets'] as num).toDouble(),
    weightedSetsPerWeek: (json['weighted_sets_per_week'] as num).toDouble(),
    band: StimulusBand.parse(json['band'] as String),
    frequency: json['frequency'] as int,
    volumeLoadKg: (json['volume_load_kg'] as num).toDouble(),
  );

  final String muscleId;
  final String name;

  /// `front`, `back` ou `both`.
  final String view;
  final double weightedSets;
  final double weightedSetsPerWeek;
  final StimulusBand band;

  /// Dias distintos com estímulo no período.
  final int frequency;
  final double volumeLoadKg;

  bool shownOn(BodyView side) => view == 'both' || view == side.name;

  BodyView get mainView => view == 'back' ? BodyView.back : BodyView.front;
}

/// Limites de uma faixa, em séries ponderadas por semana: `[mínimo, máximo)`;
/// `[x, x]` vale só para x (a faixa "nenhuma" da v2 é `[0, 0]`).
@immutable
class BandRange {
  const BandRange(this.min, this.max);

  final double min;
  final double? max;

  /// "0", "menos de 6", "6 a 12", "12 ou mais".
  String describe() {
    final low = formatDecimal(min);
    final high = max;
    if (high == null) return '$low ou mais';
    if (high == min) return low;
    if (min == 0) return 'menos de ${formatDecimal(high)}';
    return '$low a ${formatDecimal(high)}';
  }
}

/// O Meu Corpo de um período: os 13 músculos do catálogo, mesmo os zerados.
@immutable
class BodyStimulus {
  const BodyStimulus({
    required this.methodologyVersion,
    required this.periodDays,
    required this.bands,
    required this.notice,
    required this.muscles,
  });

  factory BodyStimulus.fromJson(Map<String, dynamic> json) => BodyStimulus(
    methodologyVersion: json['methodology_version'] as String,
    periodDays: json['period_days'] as int,
    bands: {
      for (final MapEntry(:key, :value)
          in (json['bands'] as Map<String, dynamic>).entries)
        StimulusBand.parse(key): BandRange(
          ((value as List)[0] as num).toDouble(),
          (value[1] as num?)?.toDouble(),
        ),
    },
    notice: json['notice'] as String,
    muscles: [
      for (final m in json['muscles'] as List)
        MuscleStimulus.fromJson(m as Map<String, dynamic>),
    ],
  );

  final String methodologyVersion;
  final int periodDays;
  final Map<StimulusBand, BandRange> bands;
  final String notice;
  final List<MuscleStimulus> muscles;

  bool get isEmpty => muscles.every((m) => m.weightedSets == 0);

  MuscleStimulus? muscle(String id) {
    for (final m in muscles) {
      if (m.muscleId == id) return m;
    }
    return null;
  }

  /// Os músculos com o menor estímulo do período (empatados, todos), para
  /// responder "qual recebeu menos" (tarefa do teste de usabilidade).
  List<MuscleStimulus> get leastStimulated {
    final least = muscles
        .map((m) => m.weightedSetsPerWeek)
        .fold<double?>(null, (a, b) => a == null || b < a ? b : a);
    return [
      for (final m in muscles)
        if (m.weightedSetsPerWeek == least) m,
    ];
  }
}

@immutable
class MuscleExercise {
  const MuscleExercise({
    required this.exerciseId,
    required this.name,
    required this.role,
    required this.weightedSets,
    required this.sets,
    this.bestLoadKg,
  });

  factory MuscleExercise.fromJson(Map<String, dynamic> json) => MuscleExercise(
    exerciseId: json['exercise_id'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
    weightedSets: (json['weighted_sets'] as num).toDouble(),
    sets: json['sets'] as int,
    bestLoadKg: (json['best_load_kg'] as num?)?.toDouble(),
  );

  final String exerciseId;
  final String name;

  /// `primary` ou `secondary`.
  final String role;
  final double weightedSets;

  /// Séries válidas (sem aquecimento; segmentos de drop não são série nova).
  final int sets;
  final double? bestLoadKg;
}

@immutable
class LoadPoint {
  const LoadPoint({
    required this.day,
    required this.exerciseId,
    required this.bestLoadKg,
  });

  factory LoadPoint.fromJson(Map<String, dynamic> json) => LoadPoint(
    day: DateTime.parse(json['day'] as String),
    exerciseId: json['exercise_id'] as String,
    bestLoadKg: (json['best_load_kg'] as num).toDouble(),
  );

  final DateTime day;
  final String exerciseId;
  final double bestLoadKg;
}

/// O período anterior do mesmo tamanho, para comparar.
@immutable
class PreviousStimulus {
  const PreviousStimulus({
    required this.weightedSetsPerWeek,
    required this.frequency,
    required this.band,
    required this.difference,
    this.percent,
  });

  factory PreviousStimulus.fromJson(Map<String, dynamic> json) =>
      PreviousStimulus(
        weightedSetsPerWeek: (json['weighted_sets_per_week'] as num).toDouble(),
        frequency: json['frequency'] as int,
        band: StimulusBand.parse(json['band'] as String),
        difference: (json['difference'] as num).toDouble(),
        percent: (json['percent'] as num?)?.toDouble(),
      );

  final double weightedSetsPerWeek;
  final int frequency;
  final StimulusBand band;

  /// Séries por semana: atual menos anterior.
  final double difference;

  /// Só com base válida (anterior > 0).
  final double? percent;

  /// "+1,5 série/semana (+20%) vs. 30 dias anteriores".
  String describe(int days) {
    final reference = 'vs. $days dias anteriores';
    if (difference == 0) return 'Igual aos $days dias anteriores.';
    final sign = difference > 0 ? '+' : '−';
    final amount = difference.abs();
    final unit = amount == 1 ? 'série/semana' : 'séries/semana';
    final value = '$sign${formatDecimal(amount)} $unit';
    final p = percent;
    return p == null
        ? '$value $reference'
        : '$value ($sign${formatDecimal(p.abs().round())}%) $reference';
  }
}

@immutable
class MuscleDetail {
  const MuscleDetail({
    required this.periodDays,
    required this.notice,
    required this.muscle,
    required this.exercises,
    required this.loads,
    this.previous,
  });

  factory MuscleDetail.fromJson(Map<String, dynamic> json) => MuscleDetail(
    periodDays: json['period_days'] as int,
    notice: json['notice'] as String,
    muscle: MuscleStimulus.fromJson(json['muscle'] as Map<String, dynamic>),
    exercises: [
      for (final e in json['exercises'] as List)
        MuscleExercise.fromJson(e as Map<String, dynamic>),
    ],
    loads: [
      for (final p in json['loads'] as List)
        LoadPoint.fromJson(p as Map<String, dynamic>),
    ],
    previous: json['previous'] == null
        ? null
        : PreviousStimulus.fromJson(json['previous'] as Map<String, dynamic>),
  );

  final int periodDays;
  final String notice;
  final MuscleStimulus muscle;
  final List<MuscleExercise> exercises;
  final List<LoadPoint> loads;
  final PreviousStimulus? previous;

  /// A maior carga por dia de um exercício, em ordem de data.
  List<LoadPoint> loadsOf(String exerciseId) => [
    for (final p in loads)
      if (p.exerciseId == exerciseId) p,
  ]..sort((a, b) => a.day.compareTo(b.day));
}
