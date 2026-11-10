import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_selection.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../activities/domain/activity.dart';
import '../../goals/presentation/goal_format.dart';
import '../application/analytics_controller.dart';
import '../domain/analytics.dart';

const _modalityLabels = {
  'strength': 'Musculação',
  'run': 'Corrida',
  'walk': 'Caminhada',
  'cycle': 'Ciclismo',
  'swim': 'Natação',
};

/// Frequência, consistência e comparação com o período anterior (etapa 3.4).
/// Os gráficos chegam na 3.7.
class EvolutionPage extends ConsumerStatefulWidget {
  const EvolutionPage({super.key});

  @override
  ConsumerState<EvolutionPage> createState() => _EvolutionPageState();
}

class _EvolutionPageState extends ConsumerState<EvolutionPage> {
  AnalyticsPeriod _period = AnalyticsPeriod.options[1];

  @override
  Widget build(BuildContext context) {
    final evolution = ref.watch(evolutionProvider(_period));
    return Scaffold(
      appBar: AppBar(title: const Text('Evolução')),
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
            const SizedBox(height: EvoSpace.lg),
            _WeekBars(weeks: overview.weekList),
          ],
        ),
      ),
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
      if (data.run case final run?) ...[
        const SizedBox(height: EvoSpace.md),
        _RunCard(run: run),
      ],
    ];
  }
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

/// Barras simples de sessões por semana (os gráficos completos são da 3.7).
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.weeks});

  final List<WeekSummary> weeks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final most = weeks.fold<int>(0, (m, w) => w.sessions > m ? w.sessions : m);
    // Com muitas semanas (90 dias), só as 6 últimas: a lista inteira vira gráfico na 3.7.
    final shown = weeks.length > 6 ? weeks.sublist(weeks.length - 6) : weeks;
    return Column(
      children: [
        for (final week in shown)
          Semantics(
            label:
                'Semana de ${localizations.formatShortMonthDay(week.weekStart)}: '
                '${week.sessions} ${week.sessions == 1 ? 'sessão' : 'sessões'}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: EvoSpace.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      localizations.formatShortMonthDay(week.weekStart),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: most == 0 ? 0 : week.sessions / most,
                        minHeight: 10,
                        backgroundColor: EvoColors.bgElevated,
                        color: EvoColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: EvoSpace.sm),
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${week.sessions}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
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
                  _modalityLabels[summary.modality] ?? summary.modality,
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

class _RunCard extends StatelessWidget {
  const _RunCard({required this.run});

  final EnduranceSummary run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trend = switch (run.trend) {
      'up' => 'Distância semanal subindo',
      'down' => 'Distância semanal caindo',
      'flat' => 'Distância semanal estável',
      _ => 'Tendência a partir de 3 semanas completas',
    };
    return EvoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Corrida', style: theme.textTheme.titleMedium),
          const SizedBox(height: EvoSpace.xs),
          Text(
            [
              formatDistance(run.distanceM, modality: 'run'),
              if (run.paceSPerKm case final pace?)
                'pace médio ${formatPace(pace, per: 'km')}',
            ].join(' · '),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: EvoSpace.xs),
          Text(trend, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
