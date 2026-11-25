/// Peso e medidas (5.3, contrato em docs/API.md §Fase 5).
library;

import '../../goals/presentation/goal_format.dart' show formatDecimal;

/// As medidas na ordem da API (usada antes de a lista dela chegar).
const metricOrder = [
  'weight_kg',
  'body_fat_pct',
  'waist_cm',
  'hip_cm',
  'chest_cm',
  'arm_cm',
  'thigh_cm',
  'calf_cm',
];

class MetricInfo {
  const MetricInfo({
    required this.metric,
    required this.label,
    required this.unit,
    required this.min,
    required this.max,
    this.estimate = false,
  });

  factory MetricInfo.fromJson(Map<String, dynamic> json) => MetricInfo(
    metric: json['metric'] as String,
    label: json['label'] as String,
    unit: json['unit'] as String,
    min: (json['min'] as num).toDouble(),
    max: (json['max'] as num).toDouble(),
    estimate: json['estimate'] as bool,
  );

  final String metric;
  final String label;

  /// kg | % | cm
  final String unit;
  final double min;
  final double max;

  /// Gordura corporal: estimativa de balança ou dobras.
  final bool estimate;
}

/// "72,4 kg", "18,5 %", "81 cm".
String formatMeasure(double value, String unit) =>
    '${formatDecimal(_tenth(value))} $unit';

/// "−1,2 kg", "+0,4 cm", "0 kg" (o sinal de menos tipográfico).
String formatChange(double value, String unit) {
  final rounded = _tenth(value);
  if (rounded == 0) return '0 $unit';
  final sign = rounded > 0 ? '+' : '−';
  return '$sign${formatDecimal(rounded.abs())} $unit';
}

double _tenth(double value) => (value * 10).roundToDouble() / 10;

class Measurement {
  const Measurement({
    required this.id,
    required this.localTime,
    required this.values,
    this.notes,
  });

  factory Measurement.fromJson(Map<String, dynamic> json) => Measurement(
    id: json['id'] as String,
    // Horário no fuso do perfil, sem fuso: o que a pessoa vê e edita.
    localTime: DateTime.parse(json['local_time'] as String),
    values: {
      for (final metric in metricOrder)
        if (json[metric] case final num value) metric: value.toDouble(),
    },
    notes: json['notes'] as String?,
  );

  final String id;
  final DateTime localTime;

  /// Só as medidas preenchidas.
  final Map<String, double> values;
  final String? notes;
}

class TrendPoint {
  const TrendPoint({
    required this.date,
    required this.value,
    required this.average7d,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
    date: DateTime.parse(json['date'] as String),
    value: (json['value'] as num).toDouble(),
    average7d: (json['average_7d'] as num).toDouble(),
  );

  final DateTime date;
  final double value;
  final double average7d;
}

class Trend {
  const Trend({
    required this.metric,
    required this.label,
    required this.unit,
    required this.points,
    this.change,
    this.weeklyRate,
  });

  factory Trend.fromJson(Map<String, dynamic> json) => Trend(
    metric: json['metric'] as String,
    label: json['label'] as String,
    unit: json['unit'] as String,
    points: [
      for (final p in json['points'] as List<dynamic>)
        TrendPoint.fromJson(p as Map<String, dynamic>),
    ],
    change: (json['change'] as num?)?.toDouble(),
    weeklyRate: (json['weekly_rate'] as num?)?.toDouble(),
  );

  final String metric;
  final String label;
  final String unit;
  final List<TrendPoint> points;

  /// Último menos o primeiro do período.
  final double? change;

  /// Ritmo por semana; nulo com poucos pontos ou menos de 14 dias.
  final double? weeklyRate;
}

/// Períodos da tela, em dias.
const measurementPeriods = [30, 90, 180, 365];
