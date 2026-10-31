import 'package:flutter/material.dart';

/// Ícone de cada tipo de meta; tipos novos da API usam a bandeira.
IconData goalKindIcon(String kind) => switch (kind) {
  'strength' => Icons.fitness_center_rounded,
  'hypertrophy' => Icons.accessibility_new_rounded,
  'weight_loss' => Icons.trending_down_rounded,
  'weight_gain' => Icons.trending_up_rounded,
  'weight_maintenance' => Icons.balance_rounded,
  'run_distance' => Icons.directions_run_rounded,
  'run_time' => Icons.timer_outlined,
  'frequency' => Icons.calendar_month_rounded,
  'habit' => Icons.repeat_rounded,
  _ => Icons.flag_outlined,
};

/// Número no formato brasileiro, sem casas decimais desnecessárias (82,5; 80).
String formatDecimal(num value) {
  final text = value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return text.replaceAll('.', ',');
}

/// Lê "82,5" ou "82.5". Nulo se não for um número.
double? parseDecimal(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

/// Segundos como "25:30" ou "1:05:00".
String formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(secs)}'
      : '$minutes:${two(secs)}';
}

/// Lê "mm:ss" ou "h:mm:ss" (minutos e segundos até 59). Nulo se inválido.
int? parseDuration(String text) {
  final parts = text.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.any((n) => n == null || n < 0)) return null;
  final values = numbers.cast<int>();
  final (hours, minutes, seconds) = values.length == 3
      ? (values[0], values[1], values[2])
      : (0, values[0], values[1]);
  if (seconds > 59 || (values.length == 3 && minutes > 59)) return null;
  return hours * 3600 + minutes * 60 + seconds;
}

/// Data no idioma do app: "seg., 30 de nov." neste ano; "30/11/2027" em outro ano,
/// porque o formato médio não mostra o ano.
String formatGoalDate(BuildContext context, DateTime date) {
  final localizations = MaterialLocalizations.of(context);
  return date.year == DateTime.now().year
      ? localizations.formatMediumDate(date)
      : localizations.formatCompactDate(date);
}
