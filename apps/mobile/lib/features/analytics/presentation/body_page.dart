import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_selection.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../goals/presentation/goal_format.dart';
import '../application/analytics_controller.dart';
import '../domain/analytics.dart';
import '../domain/body.dart';
import 'body_map.dart';
import 'charts.dart';

const _custom = 'custom';

String _perWeek(double value) =>
    '${formatDecimal(value)} ${value == 1 ? 'série' : 'séries'}/semana';

/// Meu Corpo 2D (etapa 3.6): mapa frente/costas colorido pelas faixas de estímulo
/// da API, período, legenda e o detalhe de cada músculo.
class BodyPage extends ConsumerStatefulWidget {
  const BodyPage({super.key});

  @override
  ConsumerState<BodyPage> createState() => _BodyPageState();
}

class _BodyPageState extends ConsumerState<BodyPage> {
  AnalyticsPeriod _period = AnalyticsPeriod.options[1];
  BodyView _view = BodyView.front;
  String? _selected;

  Future<void> _pickRange() async {
    final today = AnalyticsPeriod.options.first.to;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
      initialDateRange: DateTimeRange(start: _period.from, end: _period.to),
      helpText: 'Escolha o período',
      saveText: 'Aplicar',
    );
    if (range == null || !mounted) return;
    final period = AnalyticsPeriod.range(range.start, range.end);
    if (period.days > AnalyticsPeriod.maxDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha um período de até 366 dias.')),
      );
      return;
    }
    setState(() => _period = period);
  }

  Future<void> _open(MuscleStimulus muscle) async {
    setState(() {
      _selected = muscle.muscleId;
      if (!muscle.shownOn(_view)) _view = muscle.mainView;
    });
    await showMuscleSheet(context, muscle: muscle, period: _period);
    if (mounted) setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final body = ref.watch(bodyProvider(_period));
    final localizations = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Meu Corpo')),
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
                (_custom, 'Outro período'),
              ],
              selected: {_period.isCustom ? _custom : '${_period.days}'},
              onChanged: (selected) {
                final code = selected.first;
                if (code == _custom) {
                  _pickRange();
                } else {
                  setState(() => _period = AnalyticsPeriod(int.parse(code)));
                }
              },
            ),
            if (_period.isCustom) ...[
              const SizedBox(height: EvoSpace.sm),
              Text(
                '${localizations.formatShortDate(_period.from)} a '
                '${localizations.formatShortDate(_period.to)} '
                '(${_period.days} dias)',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: EvoSpace.lg),
            ...body.when(
              loading: () => const [EvoLoadingView(lines: 6)],
              error: (error, _) => [
                EvoErrorView(
                  title: 'Não foi possível calcular o Meu Corpo',
                  message: error is ApiException
                      ? error.message
                      : 'Erro inesperado.',
                  onRetry: () => ref.invalidate(bodyProvider(_period)),
                ),
              ],
              data: (data) => _content(context, data),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, BodyStimulus data) {
    final theme = Theme.of(context);
    final bands = {for (final m in data.muscles) m.muscleId: m.band};
    final visible = [
      for (final m in data.muscles)
        if (m.shownOn(_view)) m,
    ];
    final least = data.leastStimulated;
    return [
      Center(
        child: EvoChipGroup(
          single: true,
          options: [for (final v in BodyView.values) (v.name, v.label)],
          selected: {_view.name},
          onChanged: (selected) =>
              setState(() => _view = BodyView.values.byName(selected.first)),
        ),
      ),
      const SizedBox(height: EvoSpace.md),
      // O mapa é a forma visual; quem usa leitor de tela tem a mesma informação
      // (e o mesmo toque) na lista de músculos abaixo.
      Semantics(
        label:
            'Mapa do corpo, ${_view.label.toLowerCase()}: '
            '${visible.map((m) => '${m.name}, ${m.band.label}').join('; ')}',
        excludeSemantics: true,
        child: SizedBox(
          height: 380,
          child: BodyMap(
            key: const ValueKey('body-map'),
            view: _view,
            bands: bands,
            selected: _selected,
            onSelect: (id) => _open(data.muscle(id)!),
          ),
        ),
      ),
      const SizedBox(height: EvoSpace.md),
      _Legend(data: data),
      const SizedBox(height: EvoSpace.xl),
      if (data.isEmpty)
        EvoCard(
          child: Text(
            'Nenhuma série de musculação concluída nesses '
            '${data.periodDays} dias. Os músculos ganham cor conforme as '
            'séries dos treinos concluídos.',
            style: theme.textTheme.bodyMedium,
          ),
        )
      else
        EvoCard(
          child: Text(
            least.first.weightedSets == 0
                ? 'Sem nenhuma série em ${data.periodDays} dias: '
                      '${_names(least)}.'
                : 'Com menos estímulo: ${_names(least)} '
                      '(${_perWeek(least.first.weightedSetsPerWeek)}).',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      const SizedBox(height: EvoSpace.xl),
      Semantics(
        header: true,
        child: Text('Músculos', style: theme.textTheme.titleLarge),
      ),
      const SizedBox(height: EvoSpace.sm),
      EvoCard(
        padding: const EdgeInsets.symmetric(vertical: EvoSpace.xs),
        child: Column(
          children: [
            for (final muscle in data.muscles)
              _MuscleRow(muscle: muscle, onTap: () => _open(muscle)),
          ],
        ),
      ),
    ];
  }

  /// Todos os nomes ("A, B e C"): é a resposta de "qual recebeu menos".
  static String _names(List<MuscleStimulus> muscles) {
    final names = muscles.map((m) => m.name).toList();
    return names.length == 1
        ? names.single
        : '${names.sublist(0, names.length - 1).join(', ')} e ${names.last}';
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.data});

  final BodyStimulus data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Séries por semana', style: theme.textTheme.titleSmall),
          const SizedBox(height: EvoSpace.sm),
          Wrap(
            spacing: EvoSpace.lg,
            runSpacing: EvoSpace.sm,
            children: [
              for (final band in StimulusBand.values)
                if (data.bands[band] case final range?)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Swatch(band: band),
                      const SizedBox(width: EvoSpace.xs),
                      Flexible(
                        child: Text(
                          '${band.label}: ${range.describe()}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
            ],
          ),
          const SizedBox(height: EvoSpace.sm),
          Text(
            '${data.notice} Metodologia ${data.methodologyVersion}.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: EvoColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.band});

  final StimulusBand band;

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: bandColor(band),
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

class _MuscleRow extends StatelessWidget {
  const _MuscleRow({required this.muscle, required this.onTap});

  final MuscleStimulus muscle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: evoTouchTargetMin),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: EvoSpace.lg,
            vertical: EvoSpace.sm,
          ),
          child: Row(
            children: [
              _Swatch(band: muscle.band),
              const SizedBox(width: EvoSpace.md),
              Expanded(
                child: Text(muscle.name, style: theme.textTheme.bodyLarge),
              ),
              const SizedBox(width: EvoSpace.sm),
              Flexible(
                child: Text(
                  '${formatDecimal(muscle.weightedSetsPerWeek)}/sem · '
                  '${muscle.band.label}',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showMuscleSheet(
  BuildContext context, {
  required MuscleStimulus muscle,
  required AnalyticsPeriod period,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _MuscleSheet(muscle: muscle, period: period),
);

class _MuscleSheet extends ConsumerWidget {
  const _MuscleSheet({required this.muscle, required this.period});

  final MuscleStimulus muscle;
  final AnalyticsPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = (muscle.muscleId, period);
    final detail = ref.watch(muscleDetailProvider(key));
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          EvoSpace.xl,
          0,
          EvoSpace.xl,
          EvoSpace.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(muscle.name, style: theme.textTheme.titleLarge),
                ),
                _Swatch(band: muscle.band),
                const SizedBox(width: EvoSpace.xs),
                Text(muscle.band.label, style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: EvoSpace.md),
            ...detail.when(
              loading: () => const [EvoLoadingView(lines: 3)],
              error: (error, _) => [
                EvoErrorView(
                  title: 'Não foi possível abrir o músculo',
                  message: error is ApiException
                      ? error.message
                      : 'Erro inesperado.',
                  onRetry: () => ref.invalidate(muscleDetailProvider(key)),
                ),
              ],
              data: (data) => _content(context, data),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, MuscleDetail data) {
    final theme = Theme.of(context);
    final m = data.muscle;
    final days = data.periodDays;
    final localizations = MaterialLocalizations.of(context);
    final trained = m.weightedSets > 0;
    return [
      if (trained) ...[
        Text(
          '${_perWeek(m.weightedSetsPerWeek)} · '
          '${formatDecimal(m.weightedSets)} em $days dias',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: EvoSpace.xs),
        Text(
          [
            'Treinado em ${m.frequency} ${m.frequency == 1 ? 'dia' : 'dias'}',
            if (m.volumeLoadKg > 0)
              '${formatDecimal(m.volumeLoadKg.round())} kg de volume',
          ].join(' · '),
          style: theme.textTheme.bodyMedium,
        ),
      ] else
        Text(
          'Nenhuma série para este músculo em $days dias.',
          style: theme.textTheme.bodyMedium,
        ),
      if (data.previous case final previous?) ...[
        const SizedBox(height: EvoSpace.xs),
        Text(
          previous.describe(days),
          style: theme.textTheme.labelSmall?.copyWith(
            color: switch (previous.difference) {
              > 0 => EvoColors.success,
              < 0 => EvoColors.warning,
              _ => EvoColors.textSecondary,
            },
          ),
        ),
      ],
      if (data.exercises.isNotEmpty) ...[
        const SizedBox(height: EvoSpace.xl),
        Semantics(
          header: true,
          child: Text('Exercícios', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: EvoSpace.sm),
        for (final exercise in data.exercises)
          Padding(
            padding: const EdgeInsets.only(bottom: EvoSpace.md),
            child: _ExerciseLine(
              exercise: exercise,
              loads: data.loadsOf(exercise.exerciseId),
              localizations: localizations,
            ),
          ),
      ],
      const SizedBox(height: EvoSpace.md),
      Text(
        data.notice,
        style: theme.textTheme.labelSmall?.copyWith(
          color: EvoColors.textSecondary,
        ),
      ),
    ];
  }
}

class _ExerciseLine extends StatelessWidget {
  const _ExerciseLine({
    required this.exercise,
    required this.loads,
    required this.localizations,
  });

  final MuscleExercise exercise;
  final List<LoadPoint> loads;
  final MaterialLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String day(LoadPoint p) => localizations.formatShortMonthDay(p.day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(exercise.name, style: theme.textTheme.bodyLarge),
        Text(
          [
            exercise.role == 'primary' ? 'principal' : 'secundário',
            '${exercise.sets} ${exercise.sets == 1 ? 'série' : 'séries'}',
            '${formatDecimal(exercise.weightedSets)} ponderadas',
            if (exercise.bestLoadKg case final best?)
              'maior carga ${formatDecimal(best)} kg',
          ].join(' · '),
          style: theme.textTheme.bodyMedium,
        ),
        // Evolução da maior carga de cada dia (3.7); com um dia só, não há linha.
        if (loads.length > 1) ...[
          const SizedBox(height: EvoSpace.sm),
          EvoLineChart(
            key: ValueKey('loads-${exercise.exerciseId}'),
            title: '${exercise.name}: maior carga por dia',
            height: 140,
            points: [
              for (final p in loads)
                ChartPoint(
                  label: axisDate(p.day),
                  spoken: day(p),
                  value: p.bestLoadKg,
                ),
            ],
            format: (v) => '${formatDecimal(v)} kg',
            axisFormat: (v) => formatDecimal(v),
          ),
          Text(
            'Cargas: ${formatDecimal(loads.first.bestLoadKg)} kg '
            '(${day(loads.first)}) → ${formatDecimal(loads.last.bestLoadKg)} kg '
            '(${day(loads.last)})',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ],
    );
  }
}
