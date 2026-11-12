import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_selection.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../activities/domain/activity.dart';
import '../../goals/presentation/goal_format.dart';
import '../application/analytics_controller.dart';
import '../domain/analytics.dart';
import '../domain/compare.dart';
import 'charts.dart';

/// Frequência, consistência e comparação com o período anterior (etapa 3.4), com
/// os gráficos por semana (3.7).
class EvolutionPage extends ConsumerStatefulWidget {
  const EvolutionPage({super.key});

  @override
  ConsumerState<EvolutionPage> createState() => _EvolutionPageState();
}

class _EvolutionPageState extends ConsumerState<EvolutionPage> {
  AnalyticsPeriod _period = AnalyticsPeriod.options[1];
  _WeekMetric _weekMetric = _WeekMetric.sessions;

  @override
  Widget build(BuildContext context) {
    final evolution = ref.watch(evolutionProvider(_period));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Evolução'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push(AppRoutes.compare),
            icon: const Icon(Icons.compare_arrows_rounded),
            label: const Text('Comparar'),
          ),
          const SizedBox(width: EvoSpace.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(EvoSpace.xl),
          children: [
            EvoChipGroup(
              single: true,
              options: [
                for (final option in AnalyticsPeriod.options)
                  ('${option.days}', '${option.days} dias'),
              ],
              selected: {'${_period.days}'},
              onChanged: (selected) => setState(
                () => _period = AnalyticsPeriod(int.parse(selected.first)),
              ),
            ),
            const SizedBox(height: EvoSpace.xl),
            ...evolution.when(
              loading: () => const [EvoLoadingView(lines: 5)],
              error: (error, _) => [
                EvoErrorView(
                  title: 'Não foi possível calcular sua evolução',
                  message: error is ApiException
                      ? error.message
                      : 'Erro inesperado.',
                  onRetry: () => ref.invalidate(evolutionProvider(_period)),
                ),
              ],
              data: (data) => data.overview.sessions == 0
                  ? [
                      EvoEmptyView(
                        icon: Icons.insights_rounded,
                        title: 'Nada registrado em ${_period.days} dias',
                        message:
                            'Treinos de musculação e atividades concluídos '
                            'aparecem aqui: frequência, consistência e '
                            'comparação com o período anterior.',
                      ),
                    ]
                  : _content(context, data),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, Evolution data) {
    final theme = Theme.of(context);
    final overview = data.overview;
    final days = _period.days;
    return [
      _Stat(
        label: 'Treinos e atividades',
        value: '${overview.sessions}',
        detail: describeComparison(
          data.sessions,
          days,
          unit: (v) => '${v.round()}',
        ),
        better: data.sessions.better,
      ),
      const SizedBox(height: EvoSpace.md),
      _Stat(
        label: 'Tempo total',
        value: formatTotalDuration(overview.durationS),
        detail: describeComparison(
          data.duration,
          days,
          unit: (v) => formatTotalDuration(v.round()),
        ),
        better: data.duration.better,
      ),
      const SizedBox(height: EvoSpace.md),
      _Stat(
        label: 'Dias ativos',
        value: '${overview.activeDays} de ${overview.days}',
      ),
      const SizedBox(height: EvoSpace.xl),
      Semantics(
        header: true,
        child: Text('Consistência', style: theme.textTheme.titleLarge),
      ),
      const SizedBox(height: EvoSpace.md),
      EvoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${overview.activeWeeks} de ${overview.weeks} semanas com '
              'treino',
              style: theme.textTheme.titleMedium,
            ),
            if (overview.weeklyTarget case final target?) ...[
              const SizedBox(height: EvoSpace.xs),
              Text(
                '${overview.weeksOnTarget} com $target dias ou mais '
                '(sua meta no perfil)',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: EvoSpace.xs),
            Text(switch (overview.currentStreakWeeks) {
              0 => 'Nenhuma sequência em andamento',
              1 => 'Sequência atual: 1 semana',
              final n => 'Sequência atual: $n semanas seguidas',
            }, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
      const SizedBox(height: EvoSpace.xl),
      Semantics(
        header: true,
        child: Text('Por semana', style: theme.textTheme.titleLarge),
      ),
      const SizedBox(height: EvoSpace.md),
      _weekChart(overview),
      const SizedBox(height: EvoSpace.xl),
      Semantics(
        header: true,
        child: Text('Por modalidade', style: theme.textTheme.titleLarge),
      ),
      const SizedBox(height: EvoSpace.md),
      for (final modality in overview.modalities)
        Padding(
          padding: const EdgeInsets.only(bottom: EvoSpace.md),
          child: _ModalityCard(summary: modality),
        ),
      for (final summary in data.endurance) ...[
        const SizedBox(height: EvoSpace.md),
        _EnduranceCard(summary: summary),
      ],
    ];
  }

  Widget _weekChart(Overview overview) {
    final strength = overview.modality('strength') != null;
    final metrics = [
      _WeekMetric.sessions,
      _WeekMetric.duration,
      if (strength) ...[_WeekMetric.sets, _WeekMetric.volume],
    ];
    final metric = metrics.contains(_weekMetric)
        ? _weekMetric
        : _WeekMetric.sessions;
    final weeks = overview.weekList;
    return EvoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EvoChipGroup(
            single: true,
            options: [for (final m in metrics) (m.name, m.label)],
            selected: {metric.name},
            onChanged: (selected) => setState(
              () => _weekMetric = _WeekMetric.values.byName(selected.first),
            ),
          ),
          const SizedBox(height: EvoSpace.lg),
          EvoBarChart(
            key: const ValueKey('week-chart'),
            title: '${metric.label} por semana',
            points: weekPoints(context, [
              for (final w in weeks) (w.weekStart, metric.value(w)),
            ]),
            format: metric.format,
            axisFormat: metric.axis,
            whole: metric == _WeekMetric.sessions || metric == _WeekMetric.sets,
          ),
          const SizedBox(height: EvoSpace.sm),
          Text(
            'Semanas de segunda a domingo; a primeira e a última podem '
            'estar incompletas.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// Pontos semanais: rótulo curto ("5 de out.") e falado ("Semana de 5 de out.").
List<ChartPoint> weekPoints(
  BuildContext context,
  List<(DateTime, double?)> weeks,
) {
  final localizations = MaterialLocalizations.of(context);
  return [
    for (final (week, value) in weeks)
      ChartPoint(
        label: axisDate(week),
        spoken: 'Semana de ${localizations.formatShortMonthDay(week)}',
        value: value,
      ),
  ];
}

enum _WeekMetric {
  sessions('Treinos'),
  duration('Tempo'),
  sets('Séries'),
  volume('Volume');

  const _WeekMetric(this.label);

  final String label;

  double value(WeekSummary week) => switch (this) {
    sessions => week.sessions.toDouble(),
    duration => week.durationS / 60,
    sets => week.strengthSets.toDouble(),
    volume => week.strengthVolumeKg,
  };

  String format(double v) => switch (this) {
    sessions => v == 1 ? '1 treino' : '${formatDecimal(v)} treinos',
    duration => formatTotalDuration((v * 60).round()),
    sets => v == 1 ? '1 série' : '${formatDecimal(v)} séries',
    volume => '${formatDecimal(v.round())} kg',
  };

  String axis(double v) => switch (this) {
    duration => v >= 120 ? '${formatDecimal(v / 60)} h' : '${v.round()} min',
    volume => v >= 1000 ? '${formatDecimal(v / 1000)} t' : '${v.round()}',
    _ => formatDecimal(v),
  };
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.detail,
    this.better,
  });

  final String label;
  final String value;
  final String? detail;
  final String? better;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (better) {
      'b' => EvoColors.success,
      'a' => EvoColors.warning,
      _ => EvoColors.textSecondary,
    };
    return EvoCard(
      child: Semantics(
        label: [label, value, ?detail].join('. '),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            const SizedBox(height: EvoSpace.xs),
            Text(value, style: theme.textTheme.headlineSmall),
            if (detail != null) ...[
              const SizedBox(height: EvoSpace.xs),
              Text(
                detail!,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModalityCard extends StatelessWidget {
  const _ModalityCard({required this.summary});

  final ModalitySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strength = summary.modality == 'strength';
    final details = [
      '${summary.sessions} ${summary.sessions == 1 ? 'vez' : 'vezes'}',
      formatTotalDuration(summary.durationS),
      if (summary.distanceM case final m?)
        formatDistance(m, modality: summary.modality),
      if (strength && summary.sets != null) '${summary.sets} séries',
      if (strength && (summary.volumeKg ?? 0) > 0)
        '${formatDecimal(summary.volumeKg!.round())} kg',
    ];
    return EvoCard(
      child: Row(
        children: [
          Icon(
            strength
                ? Icons.fitness_center_rounded
                : modalityIcon(summary.modality),
          ),
          const SizedBox(width: EvoSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  modalityLabel(summary.modality),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(details.join(' · '), style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EnduranceCard extends StatelessWidget {
  const _EnduranceCard({required this.summary});

  final EnduranceSummary summary;

  /// Ritmo no formato da modalidade: pace por km, por 100 m (natação) ou
  /// velocidade (ciclismo).
  String _rhythm(double v) => switch (summary.modality) {
    'swim' => formatPace(v.round(), per: '100 m'),
    'cycle' => formatSpeed(v),
    _ => formatPace(v.round(), per: 'km'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modality = summary.modality;
    final trend = switch (summary.trend) {
      'up' => 'Distância semanal subindo',
      'down' => 'Distância semanal caindo',
      'flat' => 'Distância semanal estável',
      _ => 'Tendência a partir de 3 semanas completas',
    };
    final average = switch (modality) {
      'swim' => summary.paceSPer100m?.toDouble(),
      'cycle' => summary.speedKmh,
      _ => summary.paceSPerKm?.toDouble(),
    };
    final rhythmPoints = weekPoints(context, [
      for (final w in summary.weeks)
        (
          w.weekStart,
          switch (modality) {
            'swim' => w.paceSPer100m?.toDouble(),
            'cycle' => w.speedKmh,
            _ => w.paceSPerKm?.toDouble(),
          },
        ),
    ]);
    final rhythmWeeks = rhythmPoints.where((p) => p.value != null).length;
    final name = modalityLabel(modality);
    final cycle = modality == 'cycle';
    return EvoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: theme.textTheme.titleMedium),
          const SizedBox(height: EvoSpace.xs),
          Text(
            [
              formatDistance(summary.distanceM, modality: modality),
              if (average != null)
                '${cycle
                        ? 'velocidade média'
                        : modality == 'swim'
                        ? 'ritmo médio'
                        : 'pace médio'} '
                    '${_rhythm(average)}',
            ].join(' · '),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: EvoSpace.xs),
          Text(trend, style: theme.textTheme.labelSmall),
          if (summary.weeks.isNotEmpty) ...[
            const SizedBox(height: EvoSpace.lg),
            Text('Distância por semana', style: theme.textTheme.labelLarge),
            const SizedBox(height: EvoSpace.sm),
            EvoBarChart(
              key: ValueKey('distance-$modality'),
              title: '$name: distância por semana',
              points: weekPoints(context, [
                for (final w in summary.weeks)
                  (w.weekStart, w.distanceM.toDouble()),
              ]),
              format: (v) => formatDistance(v.round(), modality: modality),
              axisFormat: (v) => modality == 'swim'
                  ? '${v.round()} m'
                  : '${formatDecimal(v / 1000)} km',
            ),
          ],
          // Uma semana só não mostra evolução: o gráfico do ritmo pede duas.
          if (rhythmWeeks >= 2) ...[
            const SizedBox(height: EvoSpace.lg),
            Text(switch (modality) {
              'cycle' => 'Velocidade média por semana',
              'swim' => 'Ritmo por 100 m, por semana (menor é melhor)',
              _ => 'Pace por semana (menor é melhor)',
            }, style: theme.textTheme.labelLarge),
            const SizedBox(height: EvoSpace.sm),
            EvoLineChart(
              key: ValueKey('rhythm-$modality'),
              title: '$name: ${cycle ? 'velocidade' : 'pace'} por semana',
              points: rhythmPoints,
              format: _rhythm,
              steps: cycle ? EvoLineChart.decimalSteps : EvoLineChart.timeSteps,
              axisFormat: (v) =>
                  cycle ? formatDecimal(v.round()) : formatDuration(v.round()),
            ),
          ],
        ],
      ),
    );
  }
}
