import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/tokens.g.dart';

/// Um ponto de gráfico: [label] curto no eixo ("5 out."), [spoken] completo para o
/// leitor de tela e a dica ("Semana de 5 de out.") e o [value] (nulo = sem dado,
/// que não vira zero).
@immutable
class ChartPoint {
  const ChartPoint({
    required this.label,
    required this.spoken,
    required this.value,
  });

  final String label;
  final String spoken;
  final double? value;
}

/// Teto "redondo" do eixo (1, 2, 2,5 ou 5 × 10ⁿ) para as marcas não terem
/// decimais estranhos.
double niceCeiling(double value) {
  if (value <= 0) return 1;
  final magnitude = math
      .pow(10, (math.log(value) / math.ln10).floor())
      .toDouble();
  for (final step in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (value <= step * magnitude) return step * magnitude;
  }
  return 10 * magnitude;
}

/// Teto par para contagens (as marcas são 0, metade e teto): com 3 treinos, o
/// eixo vai a 4 e a marca do meio é 2, não 2,5.
double wholeCeiling(double value) {
  final top = value.ceil();
  return math.max(2, top.isEven ? top : top + 1).toDouble();
}

/// Eixo de um gráfico de linha: perto dos valores (variações pequenas, como a
/// carga ou o pace, ficam visíveis), com três marcas — mínimo, meio e máximo —
/// múltiplas do menor passo de [steps] que cobre os valores.
(double, double) lineAxis(List<double> values, List<double> steps) {
  if (values.isEmpty) return (0, 2 * steps.first);
  final high = values.reduce(math.max);
  final low = values.reduce(math.min);
  for (final step in steps) {
    var min = (low / step).floor() * step;
    // Folga embaixo quando o menor valor cairia em cima da linha do eixo.
    if (min == low && min >= step) min -= step;
    if (min + 2 * step > high) return (min, min + 2 * step);
  }
  final step = steps.last;
  final min = (low / step).floor() * step;
  final count = ((high - min) / step).ceil() + 1;
  return (min, min + count * step);
}

/// Data curta do eixo ("12/10"); a longa vai na dica e no leitor de tela.
String axisDate(DateTime day) => '${day.day}/${day.month}';

/// Descrição única do gráfico para o leitor de tela (o desenho é decorativo).
String describeChart(
  String title,
  List<ChartPoint> points,
  String Function(double value) format,
) =>
    '$title. ${[for (final p in points) '${p.spoken}: ${p.value == null ? 'sem dado' : format(p.value!)}'].join('; ')}.';

int _labelStep(int count) => math.max(1, (count / 6).ceil());

const _axisStyle = TextStyle(
  fontSize: EvoFontSize.caption,
  color: EvoColors.textSecondary,
);

FlTitlesData _titles(
  List<ChartPoint> points,
  double maxY,
  String Function(double value) axisFormat,
) {
  final step = _labelStep(points.length);
  return FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 44,
        interval: maxY / 2,
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          child: Text(axisFormat(value), style: _axisStyle),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 28,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final i = value.round();
          final last = points.length - 1;
          // Muitas semanas: rótulo a cada [step] e sempre o último, sem encostar
          // um no outro.
          final show =
              value == i &&
              i >= 0 &&
              i <= last &&
              (i == last || (i % step == 0 && last - i >= step));
          return SideTitleWidget(
            meta: meta,
            child: Text(show ? points[i].label : '', style: _axisStyle),
          );
        },
      ),
    ),
  );
}

FlGridData _grid(double maxY) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: maxY / 2,
  getDrawingHorizontalLine: (_) =>
      const FlLine(color: EvoColors.borderSubtle, strokeWidth: 1),
);

const _tooltipText = TextStyle(
  color: EvoColors.onAccent,
  fontSize: EvoFontSize.caption,
  fontWeight: FontWeight.w600,
);

/// Barras (uma por semana, normalmente). Tocar numa barra mostra o valor.
class EvoBarChart extends StatelessWidget {
  const EvoBarChart({
    super.key,
    required this.title,
    required this.points,
    required this.format,
    String Function(double value)? axisFormat,
    this.height = 180,
    this.whole = false,
  }) : axisFormat = axisFormat ?? format;

  final String title;
  final List<ChartPoint> points;

  /// Valor completo (dica e leitor de tela) e o do eixo, mais curto.
  final String Function(double value) format;
  final String Function(double value) axisFormat;
  final double height;

  /// Contagens (treinos, séries): marcas do eixo só em números inteiros.
  final bool whole;

  @override
  Widget build(BuildContext context) {
    final most = points.fold<double>(0, (m, p) => math.max(m, p.value ?? 0));
    final maxY = whole ? wholeCeiling(most) : niceCeiling(most);
    final width = math.max(
      6.0,
      math.min(22.0, 180 / math.max(points.length, 1)),
    );
    return Semantics(
      container: true,
      label: describeChart(title, points, format),
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            minY: 0,
            alignment: BarChartAlignment.spaceAround,
            borderData: FlBorderData(show: false),
            gridData: _grid(maxY),
            titlesData: _titles(points, maxY, axisFormat),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => EvoColors.accent,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                  '${points[group.x].spoken}\n${format(rod.toY)}',
                  _tooltipText,
                ),
              ),
            ),
            barGroups: [
              for (final (i, p) in points.indexed)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: p.value ?? 0,
                      width: width,
                      color: EvoColors.accent,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: maxY,
                        color: EvoColors.bgElevated,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          duration: Duration.zero,
        ),
      ),
    );
  }
}

/// Linha com um ponto por registro; pontos sem valor ficam de fora (a linha não
/// cai a zero).
class EvoLineChart extends StatelessWidget {
  const EvoLineChart({
    super.key,
    required this.title,
    required this.points,
    required this.format,
    String Function(double value)? axisFormat,
    this.height = 180,
    this.steps = decimalSteps,
  }) : axisFormat = axisFormat ?? format;

  final String title;
  final List<ChartPoint> points;
  final String Function(double value) format;
  final String Function(double value) axisFormat;
  final double height;

  /// Passos possíveis entre as marcas do eixo, do menor ao maior.
  final List<double> steps;

  /// Passos para números (carga, velocidade).
  static const decimalSteps = [
    0.5, 1.0, 2.0, 2.5, 5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 250.0, //
    500.0, 1000.0,
  ];

  /// Passos para tempo em segundos (pace): 5 s, 10 s, 15 s, 30 s, 1 min...
  static const timeSteps = [
    5.0,
    10.0,
    15.0,
    30.0,
    60.0,
    120.0,
    300.0,
    600.0,
    900.0,
    1800.0,
    3600.0,
  ];

  @override
  Widget build(BuildContext context) {
    final values = [for (final p in points) ?p.value];
    final (minY, maxY) = lineAxis(values, steps);
    return Semantics(
      container: true,
      label: describeChart(title, points, format),
      excludeSemantics: true,
      child: Container(
        height: height,
        // Folga para o último ponto e a data dele não encostarem na borda.
        padding: const EdgeInsets.only(right: EvoSpace.lg),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: math.max(points.length - 1, 1).toDouble(),
            minY: minY,
            maxY: maxY,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: (maxY - minY) / 2,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: EvoColors.borderSubtle, strokeWidth: 1),
            ),
            titlesData: _lineTitles(points, minY, maxY, axisFormat),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => EvoColors.accent,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      '${points[s.x.round()].spoken}\n${format(s.y)}',
                      _tooltipText,
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (final (i, p) in points.indexed)
                    if (p.value != null) FlSpot(i.toDouble(), p.value!),
                ],
                color: EvoColors.accent,
                barWidth: 2.5,
                dotData: FlDotData(
                  getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                    radius: 3.5,
                    color: EvoColors.accent,
                    strokeColor: EvoColors.bgSurface,
                    strokeWidth: 1.5,
                  ),
                ),
              ),
            ],
          ),
          duration: Duration.zero,
        ),
      ),
    );
  }

  static FlTitlesData _lineTitles(
    List<ChartPoint> points,
    double minY,
    double maxY,
    String Function(double value) axisFormat,
  ) {
    final base = _titles(points, maxY, axisFormat);
    return base.copyWith(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          interval: (maxY - minY) / 2,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(axisFormat(value), style: _axisStyle),
          ),
        ),
      ),
    );
  }
}
