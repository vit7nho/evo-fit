import 'package:flutter/foundation.dart';

import '../../activities/domain/activity.dart';
import '../../goals/presentation/goal_format.dart';
import 'analytics.dart';

/// Dois períodos comparados: [b] (o mais recente, normalmente) contra [a], a base
/// do percentual. Record: igualdade por valor, serve de chave de provider.
typedef PeriodPair = ({AnalyticsPeriod a, AnalyticsPeriod b});

/// Comparações prontas da tela Comparativos (3.7).
enum ComparePreset {
  week('7 dias'),
  month30('30 dias'),
  calendarMonth('Este mês'),
  custom('Escolher');

  const ComparePreset(this.label);

  final String label;

  /// Os períodos do atalho, com [today] como hoje. `custom` não tem atalho.
  PeriodPair? pair(DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    switch (this) {
      case week || month30:
        final b = AnalyticsPeriod.range(
          DateTime(day.year, day.month, day.day - (this == week ? 6 : 29)),
          day,
        );
        return (a: AnalyticsPeriod.range(b.previousFrom, b.previousTo), b: b);
      case calendarMonth:
        // Do dia 1 até hoje contra o mesmo trecho do mês passado: mês inteiro
        // contra mês pela metade não seria justo.
        final lastOfPrevious = DateTime(day.year, day.month, 0);
        final end = day.day < lastOfPrevious.day ? day.day : lastOfPrevious.day;
        return (
          a: AnalyticsPeriod.range(
            DateTime(lastOfPrevious.year, lastOfPrevious.month),
            DateTime(lastOfPrevious.year, lastOfPrevious.month, end),
          ),
          b: AnalyticsPeriod.range(DateTime(day.year, day.month), day),
        );
      case custom:
        return null;
    }
  }
}

/// Um indicador comparado, com a modalidade quando ele depende dela.
@immutable
class CompareRow {
  const CompareRow(this.comparison, {this.modality});

  final Comparison comparison;
  final String? modality;

  String get title {
    if (modality case final m?) {
      return '${comparison.label} · ${modalityLabel(m)}';
    }
    return comparison.label;
  }

  /// O valor no formato do indicador ("2 h 05 min", "6:00 /km", "1200 kg").
  String format(double value) =>
      formatMetric(comparison.metric, value, modality: modality);
}

String modalityLabel(String modality) => switch (modality) {
  'strength' => 'Musculação',
  'run' => 'Corrida',
  'walk' => 'Caminhada',
  'cycle' => 'Ciclismo',
  'swim' => 'Natação',
  _ => modality,
};

String formatMetric(String metric, double value, {String? modality}) =>
    switch (metric) {
      'duration_s' => formatTotalDuration(value.round()),
      'strength_volume_kg' => '${formatDecimal(value.round())} kg',
      'distance_m' => formatDistance(value.round(), modality: modality ?? ''),
      'pace_s_per_km' => formatPace(value.round(), per: 'km'),
      _ => formatDecimal(value),
    };

/// Frase da diferença entre os períodos ("+2 (+50%) em B", "Igual nos dois").
String describePairDifference(CompareRow row) {
  final c = row.comparison;
  final difference = c.difference;
  if (difference == null) return 'Sem dados para comparar.';
  if (difference == 0) return 'Igual nos dois períodos.';
  final sign = difference > 0 ? '+' : '−';
  final amount = '$sign${row.format(difference.abs())}';
  // No pace o sinal engana (menos é melhor): a frase diz o sentido.
  final verdict = c.higherIsBetter
      ? ''
      : switch (c.better) {
          'b' => 'mais rápido',
          'a' => 'mais lento',
          _ => '',
        };
  final percent = c.percent == null
      ? ''
      : ' ($sign${formatDecimal(c.percent!.abs().round())}%)';
  return '$amount$percent no período B${verdict.isEmpty ? '' : ' · $verdict'}';
}
