import 'package:flutter/material.dart';

import '../../goals/presentation/goal_format.dart';
import '../../profile/domain/profile.dart' show Option;

/// Códigos de modalidade da API (musculação tem a sessão de treino).
abstract final class Modalities {
  static const run = 'run';
  static const walk = 'walk';
  static const cycle = 'cycle';
  static const swim = 'swim';
}

/// Corrida, caminhada, ciclismo ou natação registrada à mão (docs/API.md).
@immutable
class Activity {
  const Activity({
    required this.id,
    required this.modality,
    required this.startedAt,
    required this.durationS,
    this.distanceM,
    this.perceivedEffort,
    this.notes,
    this.indoor,
    this.poolLengthM,
    this.laps,
    this.stroke,
  });

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
    id: json['id'] as String,
    modality: json['modality'] as String,
    startedAt: DateTime.parse(json['started_at'] as String).toLocal(),
    durationS: json['duration_s'] as int,
    distanceM: json['distance_m'] as int?,
    perceivedEffort: json['perceived_effort'] as int?,
    notes: json['notes'] as String?,
    indoor: json['indoor'] as bool?,
    poolLengthM: json['pool_length_m'] as int?,
    laps: json['laps'] as int?,
    stroke: json['stroke'] as String?,
  );

  final String id;
  final String modality;
  final DateTime startedAt;
  final int durationS;
  final int? distanceM;
  final int? perceivedEffort;
  final String? notes;

  /// Só no ciclismo.
  final bool? indoor;

  /// Só na natação (sem piscina: águas abertas).
  final int? poolLengthM;
  final int? laps;
  final String? stroke;
}

@immutable
class ModalityOption {
  const ModalityOption({
    required this.code,
    required this.label,
    required this.maxDistanceM,
  });

  factory ModalityOption.fromJson(Map<String, dynamic> json) => ModalityOption(
    code: json['code'] as String,
    label: json['label'] as String,
    maxDistanceM: json['max_distance_m'] as int,
  );

  final String code;
  final String label;
  final int maxDistanceM;
}

/// Modalidades, estilos de nado e tamanhos de piscina (GET /activity-options).
@immutable
class ActivityOptions {
  const ActivityOptions({
    required this.modalities,
    required this.strokes,
    required this.poolLengthsM,
  });

  factory ActivityOptions.fromJson(Map<String, dynamic> json) =>
      ActivityOptions(
        modalities: [
          for (final m in json['modalities'] as List<dynamic>)
            ModalityOption.fromJson(m as Map<String, dynamic>),
        ],
        strokes: [
          for (final s in json['strokes'] as List<dynamic>)
            Option.fromJson(s as Map<String, dynamic>),
        ],
        poolLengthsM: (json['pool_lengths_m'] as List<dynamic>).cast<int>(),
      );

  final List<ModalityOption> modalities;
  final List<Option> strokes;
  final List<int> poolLengthsM;

  ModalityOption? modality(String code) =>
      modalities.where((m) => m.code == code).firstOrNull;

  String modalityLabel(String code) => modality(code)?.label ?? code;

  String? strokeLabel(String? code) =>
      strokes.where((s) => s.code == code).firstOrNull?.label;
}

/// Ícone de cada modalidade; modalidades novas da API usam o cronômetro.
IconData modalityIcon(String modality) => switch (modality) {
  Modalities.run => Icons.directions_run_rounded,
  Modalities.walk => Icons.directions_walk_rounded,
  Modalities.cycle => Icons.directions_bike_rounded,
  Modalities.swim => Icons.pool_rounded,
  _ => Icons.timer_outlined,
};

/// Natação em metros; as outras em km a partir de 1 km ("5,27 km", "800 m").
String formatDistance(int meters, {required String modality}) {
  if (modality == Modalities.swim || meters < 1000) return '$meters m';
  return '${formatDecimal(meters / 1000)} km';
}
