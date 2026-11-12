import 'package:flutter/foundation.dart';

import '../../goals/presentation/goal_format.dart';

/// Período analisado: os últimos [days] dias até hoje (inclusive) ou, com
/// [AnalyticsPeriod.range], um intervalo escolhido (Meu Corpo, 3.6).
@immutable
class AnalyticsPeriod {
  const AnalyticsPeriod(this.days) : _end = null;

  /// De [from] a [to], inclusive (só as datas contam).
  AnalyticsPeriod.range(DateTime from, DateTime to)
    : days =
          DateTime.utc(
            to.year,
            to.month,
            to.day,
          ).difference(DateTime.utc(from.year, from.month, from.day)).inDays +
          1,
      _end = DateTime(to.year, to.month, to.day);

  final int days;
  final DateTime? _end;

  /// O maior período que a API aceita.
  static const maxDays = 366;

  static const options = [
    AnalyticsPeriod(7),
    AnalyticsPeriod(30),
    AnalyticsPeriod(90),
  ];

  /// Escolhido no calendário, e não "os últimos N dias".
  bool get isCustom => _end != null;

  DateTime get to {
    if (_end case final end?) return end;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get from => _shift(to, -(days - 1));

  /// O período imediatamente anterior, do mesmo tamanho (para comparar).
  DateTime get previousTo => _shift(from, -1);
  DateTime get previousFrom => _shift(previousTo, -(days - 1));

  // Pelo calendário, e não por 24 h: imune a horário de verão.
  static DateTime _shift(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);

  @override
  bool operator ==(Object other) =>
      other is AnalyticsPeriod && other.days == days && other._end == _end;

  @override
  int get hashCode => Object.hash(days, _end);
}

String apiDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

@immutable
class WeekSummary {
  const WeekSummary({
    required this.weekStart,
    required this.activeDays,
    required this.sessions,
    required this.durationS,
    this.strengthSets = 0,
    this.strengthVolumeKg = 0,
  });

  factory WeekSummary.fromJson(Map<String, dynamic> json) => WeekSummary(
    weekStart: DateTime.parse(json['week_start'] as String),
    activeDays: json['active_days'] as int,
    sessions: json['sessions'] as int,
    durationS: json['duration_s'] as int,
    strengthSets: json['strength_sets'] as int? ?? 0,
    strengthVolumeKg: (json['strength_volume_kg'] as num?)?.toDouble() ?? 0,
  );

  final DateTime weekStart;
  final int activeDays;
  final int sessions;
  final int durationS;

  /// Só da musculação (séries válidas e volume em kg).
  final int strengthSets;
  final double strengthVolumeKg;
}

@immutable
class ModalitySummary {
  const ModalitySummary({
    required this.modality,
    required this.sessions,
    required this.durationS,
    this.distanceM,
    this.sets,
    this.volumeKg,
  });

  factory ModalitySummary.fromJson(Map<String, dynamic> json) =>
      ModalitySummary(
        modality: json['modality'] as String,
        sessions: json['sessions'] as int,
        durationS: json['duration_s'] as int,
        distanceM: json['distance_m'] as int?,
        sets: json['sets'] as int?,
        volumeKg: (json['volume_kg'] as num?)?.toDouble(),
      );

  final String modality;
  final int sessions;
  final int durationS;
  final int? distanceM;
  final int? sets;
  final double? volumeKg;
}

/// Frequência, consistência e resumo por modalidade (GET /analytics/overview).
@immutable
class Overview {
  const Overview({
    required this.days,
    required this.sessions,
    required this.activeDays,
    required this.durationS,
    required this.weeks,
    required this.activeWeeks,
    required this.currentStreakWeeks,
    required this.weekList,
    required this.modalities,
    this.weeklyTarget,
    this.weeksOnTarget,
  });

  factory Overview.fromJson(Map<String, dynamic> json) {
    final consistency = json['consistency'] as Map<String, dynamic>;
    return Overview(
      days: json['days'] as int,
      sessions: json['sessions'] as int,
      activeDays: json['active_days'] as int,
      durationS: json['duration_s'] as int,
      weeklyTarget: json['weekly_target'] as int?,
      weeks: consistency['weeks'] as int,
      activeWeeks: consistency['active_weeks'] as int,
      weeksOnTarget: consistency['weeks_on_target'] as int?,
      currentStreakWeeks: consistency['current_streak_weeks'] as int,
      weekList: (json['weeks'] as List<dynamic>)
          .map((w) => WeekSummary.fromJson(w as Map<String, dynamic>))
          .toList(),
      modalities: (json['modalities'] as List<dynamic>)
          .map((m) => ModalitySummary.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }

  final int days;
  final int sessions;
  final int activeDays;
  final int durationS;
  final int? weeklyTarget;
  final int weeks;
  final int activeWeeks;
  final int? weeksOnTarget;
  final int currentStreakWeeks;
  final List<WeekSummary> weekList;
  final List<ModalitySummary> modalities;

  ModalitySummary? modality(String code) =>
      modalities.where((m) => m.modality == code).firstOrNull;
}

/// Uma semana de uma modalidade de resistência. O ritmo é nulo sem distância.
@immutable
class EnduranceWeek {
  const EnduranceWeek({
    required this.weekStart,
    required this.sessions,
    required this.distanceM,
    this.paceSPerKm,
    this.speedKmh,
    this.paceSPer100m,
  });

  factory EnduranceWeek.fromJson(Map<String, dynamic> json) => EnduranceWeek(
    weekStart: DateTime.parse(json['week_start'] as String),
    sessions: json['sessions'] as int,
    distanceM: json['distance_m'] as int,
    paceSPerKm: json['pace_s_per_km'] as int?,
    speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
    paceSPer100m: json['pace_s_per_100m'] as int?,
  );

  final DateTime weekStart;
  final int sessions;
  final int distanceM;
  final int? paceSPerKm;
  final double? speedKmh;
  final int? paceSPer100m;
}

/// Distância e ritmo de uma modalidade (GET /analytics/endurance).
@immutable
class EnduranceSummary {
  const EnduranceSummary({
    required this.sessions,
    required this.distanceM,
    this.modality = 'run',
    this.paceSPerKm,
    this.speedKmh,
    this.paceSPer100m,
    this.trend,
    this.weeks = const [],
  });

  factory EnduranceSummary.fromJson(Map<String, dynamic> json) =>
      EnduranceSummary(
        modality: json['modality'] as String? ?? 'run',
        sessions: json['sessions'] as int,
        distanceM: json['distance_m'] as int,
        paceSPerKm: json['pace_s_per_km'] as int?,
        speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
        paceSPer100m: json['pace_s_per_100m'] as int?,
        trend:
            (json['distance_trend'] as Map<String, dynamic>)['direction']
                as String?,
        weeks: [
          for (final w in json['weeks'] as List<dynamic>? ?? const [])
            EnduranceWeek.fromJson(w as Map<String, dynamic>),
        ],
      );

  final String modality;
  final int sessions;
  final int distanceM;
  final int? paceSPerKm;
  final double? speedKmh;
  final int? paceSPer100m;

  /// up | down | flat; nulo com poucas semanas.
  final String? trend;
  final List<EnduranceWeek> weeks;
}

/// Um indicador em dois períodos (GET /analytics/compare). [percent] só vem com
/// base válida (o período anterior maior que zero).
@immutable
class Comparison {
  const Comparison({
    required this.previous,
    required this.current,
    this.difference,
    this.percent,
    this.better,
    this.metric = '',
    this.label = '',
    this.higherIsBetter = true,
  });

  factory Comparison.fromJson(Map<String, dynamic> json) => Comparison(
    metric: json['metric'] as String? ?? '',
    label: json['label'] as String? ?? '',
    higherIsBetter: json['higher_is_better'] as bool? ?? true,
    previous: ((json['a'] as Map<String, dynamic>)['value'] as num?)
        ?.toDouble(),
    current: ((json['b'] as Map<String, dynamic>)['value'] as num?)?.toDouble(),
    difference: (json['difference'] as num?)?.toDouble(),
    percent: (json['percent'] as num?)?.toDouble(),
    better: json['better'] as String?,
  );

  final String metric;
  final String label;

  /// Falso no pace: menor é melhor.
  final bool higherIsBetter;

  final double? previous;
  final double? current;
  final double? difference;
  final double? percent;

  /// a (anterior), b (atual) ou same.
  final String? better;
}

/// "2 h 05 min", "45 min", "0 min".
String formatTotalDuration(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0
      ? '${minutes ~/ 60} h'
      : '${minutes ~/ 60} h ${rest.toString().padLeft(2, '0')} min';
}

/// Frase da comparação com o período anterior. [unit] formata a diferença.
String describeComparison(
  Comparison comparison,
  int days, {
  required String Function(double value) unit,
}) {
  final difference = comparison.difference;
  if (difference == null) return 'Sem dados para comparar.';
  final reference = 'vs. $days dias anteriores';
  if (difference == 0) return 'Igual aos $days dias anteriores.';
  final sign = difference > 0 ? '+' : '−';
  final amount = '$sign${unit(difference.abs())}';
  final percent = comparison.percent;
  // Sem base (anterior = 0), não há percentual: de 0 para 3 não é "+∞%".
  return percent == null
      ? '$amount $reference'
      : '$amount ($sign${formatDecimal(percent.abs().round())}%) $reference';
}
