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
    this.elevationGainM,
    this.avgHr,
    this.maxHr,
    this.paceSPerKm,
    this.speedKmh,
    this.paceSPer100m,
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
    elevationGainM: json['elevation_gain_m'] as int?,
    avgHr: json['avg_hr'] as int?,
    maxHr: json['max_hr'] as int?,
    paceSPerKm: json['pace_s_per_km'] as int?,
    speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
    paceSPer100m: json['pace_s_per_100m'] as int?,
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
  final int? elevationGainM;

  /// Frequência cardíaca (bpm): dado de saúde.
  final int? avgHr;
  final int? maxHr;

  /// Calculados pela API com distância e duração (não são guardados).
  final int? paceSPerKm;
  final double? speedKmh;
  final int? paceSPer100m;

  /// O ritmo como a modalidade costuma ver: km/h no ciclismo, pace por 100 m na
  /// natação, pace por km nas outras. Nulo sem distância.
  String? get rhythm => switch (modality) {
    Modalities.cycle => speedKmh == null ? null : formatSpeed(speedKmh!),
    Modalities.swim =>
      paceSPer100m == null ? null : formatPace(paceSPer100m!, per: '100 m'),
    _ => paceSPerKm == null ? null : formatPace(paceSPerKm!, per: 'km'),
  };

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

/// Pace como "6:00 /km" ou "2:05 /100 m".
String formatPace(int seconds, {required String per}) =>
    '${formatDuration(seconds)} /$per';

/// Velocidade como "28,4 km/h".
String formatSpeed(double kmh) => '${formatDecimal(kmh)} km/h';

/// O ritmo calculado na hora, enquanto a pessoa digita (mesma conta da API).
String? liveRhythm(String modality, int? distanceM, int? durationS) {
  if (distanceM == null ||
      distanceM < 1 ||
      durationS == null ||
      durationS < 1) {
    return null;
  }
  return switch (modality) {
    Modalities.cycle => formatSpeed(
      double.parse((distanceM / durationS * 3.6).toStringAsFixed(1)),
    ),
    Modalities.swim => formatPace(
      (durationS / distanceM * 100).round(),
      per: '100 m',
    ),
    _ => formatPace((durationS / distanceM * 1000).round(), per: 'km'),
  };
}

/// Natação em metros; as outras em km a partir de 1 km ("5,27 km", "800 m").
String formatDistance(int meters, {required String modality}) {
  if (modality == Modalities.swim || meters < 1000) return '$meters m';
  return '${formatDecimal(meters / 1000)} km';
}
