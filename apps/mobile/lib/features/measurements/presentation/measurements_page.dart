import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../analytics/presentation/charts.dart';
import '../../auth/application/auth_controller.dart';
import '../../goals/presentation/goal_format.dart' show formatDecimal;
import '../../profile/application/profile_actions.dart';
import '../../profile/domain/profile.dart' show ConsentKinds;
import '../application/measurements_controller.dart';
import '../domain/measurements.dart';

/// Peso e medidas (5.3): a tendência de uma medida no período e os registros.
class MeasurementsPage extends ConsumerStatefulWidget {
  const MeasurementsPage({super.key});

  @override
  ConsumerState<MeasurementsPage> createState() => _MeasurementsPageState();
}

class _MeasurementsPageState extends ConsumerState<MeasurementsPage> {
  int _days = 90;
  String? _metric;

  Future<void> _open({Measurement? measurement}) async {
    await context.push(AppRoutes.measurementForm, extra: measurement);
    ref
      ..invalidate(measurementsProvider)
      ..invalidate(trendProvider);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).value;
    final consented =
        auth is Authenticated && auth.user.hasConsent(ConsentKinds.healthData);
    final options = ref.watch(metricOptionsProvider).value ?? const [];
    final labels = {for (final o in options) o.metric: o};
    final list = ref.watch(measurementsProvider(_days));
    return Scaffold(
      appBar: AppBar(title: const Text('Peso e medidas')),
      floatingActionButton: consented
          ? FloatingActionButton.extended(
              onPressed: () => _open(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Registrar medida'),
            )
          : null,
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            EvoSpace.xl,
            EvoSpace.md,
            EvoSpace.xl,
            96,
          ),
          children: [
            if (!consented)
              const _ConsentCard()
            else ...[
              Wrap(
                spacing: EvoSpace.sm,
                children: [
                  for (final days in measurementPeriods)
                    ChoiceChip(
                      label: Text(periodLabel(days)),
                      selected: _days == days,
                      onSelected: (_) => setState(() => _days = days),
                    ),
                ],
              ),
              const SizedBox(height: EvoSpace.lg),
              ...list.when(
                loading: () => const [EvoLoadingView(lines: 3)],
                error: (error, _) => [
                  EvoErrorView(
                    title: 'Não foi possível carregar as medidas',
                    message: error is ApiException
                        ? error.message
                        : 'Erro inesperado.',
                    onRetry: () => ref.invalidate(measurementsProvider(_days)),
                  ),
                ],
                data: (items) {
                  if (items.isEmpty) {
                    return [
                      EvoEmptyView(
                        icon: Icons.monitor_weight_outlined,
                        title: 'Nenhuma medida neste período',
                        message:
                            'Registre o peso ou as medidas para acompanhar a '
                            'tendência ao longo das semanas.',
                        actionLabel: 'Registrar medida',
                        onAction: () => _open(),
                      ),
                    ];
                  }
                  final available = [
                    for (final m in metricOrder)
                      if (items.any((i) => i.values.containsKey(m))) m,
                  ];
                  final metric = available.contains(_metric)
                      ? _metric!
                      : available.first;
                  return [
                    if (available.length > 1) ...[
                      Wrap(
                        spacing: EvoSpace.sm,
                        runSpacing: EvoSpace.sm,
                        children: [
                          for (final m in available)
                            ChoiceChip(
                              label: Text(labels[m]?.label ?? m),
                              selected: m == metric,
                              onSelected: (_) => setState(() => _metric = m),
                            ),
                        ],
                      ),
                      const SizedBox(height: EvoSpace.lg),
                    ],
                    _TrendCard(
                      metric: metric,
                      days: _days,
                      info: labels[metric],
                    ),
                    const SizedBox(height: EvoSpace.xl),
                    Semantics(
                      header: true,
                      child: Text(
                        'Registros',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: EvoSpace.sm),
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: EvoSpace.md),
                        child: _MeasurementCard(
                          measurement: item,
                          labels: labels,
                          onTap: () => _open(measurement: item),
                        ),
                      ),
                  ];
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "30 dias", "6 meses", "1 ano".
String periodLabel(int days) => switch (days) {
  180 => '6 meses',
  365 => '1 ano',
  _ => '$days dias',
};

/// "Peso 72,4 kg · Cintura 81 cm".
String describeValues(
  Map<String, double> values,
  Map<String, MetricInfo> labels,
) => [
  for (final metric in metricOrder)
    if (values[metric] case final value?)
      '${labels[metric]?.label ?? metric} '
          '${formatMeasure(value, labels[metric]?.unit ?? '')}',
].join(' · ');

class _TrendCard extends ConsumerWidget {
  const _TrendCard({required this.metric, required this.days, this.info});

  final String metric;
  final int days;
  final MetricInfo? info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final trend = ref.watch(trendProvider((metric: metric, days: days)));
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: EvoColors.textSecondary,
    );
    return EvoCard(
      child: trend.when(
        loading: () => const EvoLoadingView(lines: 2),
        error: (error, _) =>
            Text(error is ApiException ? error.message : 'Erro inesperado.'),
        data: (t) {
          final last = t.points.isEmpty ? null : t.points.last;
          if (last == null) {
            return Text('Sem ${t.label.toLowerCase()} no período');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.label, style: theme.textTheme.labelLarge),
              Text(
                formatMeasure(last.value, t.unit),
                style: theme.textTheme.displaySmall,
              ),
              Text(
                'em ${localizations.formatMediumDate(last.date)}',
                style: secondary,
              ),
              if (info?.estimate ?? false)
                Text(
                  'Estimativa (balança ou dobras cutâneas)',
                  style: secondary,
                ),
              const SizedBox(height: EvoSpace.md),
              if (t.points.length > 1) ...[
                // Desde o primeiro registro do período (não o começo do período).
                Text(
                  '${formatChange(t.change ?? 0, t.unit)} desde '
                  '${localizations.formatShortMonthDay(t.points.first.date)}',
                  style: theme.textTheme.titleSmall,
                ),
                if (t.weeklyRate case final rate?)
                  Text(
                    'Ritmo: ${formatChange(rate, t.unit)} por semana',
                    style: secondary,
                  ),
                if (last.average7d != last.value)
                  Text(
                    'Média dos últimos 7 dias: '
                    '${formatMeasure(last.average7d, t.unit)}',
                    style: secondary,
                  ),
                // Folga para o rótulo do topo do eixo não encostar no texto.
                const SizedBox(height: EvoSpace.x2xl),
                EvoLineChart(
                  title: '${t.label} por dia',
                  points: [
                    for (final p in t.points)
                      ChartPoint(
                        label: axisDate(p.date),
                        spoken: localizations.formatMediumDate(p.date),
                        value: p.value,
                      ),
                  ],
                  format: (v) => formatMeasure(v, t.unit),
                  // Só o número no eixo: com a unidade, o rótulo quebra em duas
                  // linhas.
                  axisFormat: formatDecimal,
                ),
              ] else
                Text(
                  'Registre mais vezes para ver a tendência.',
                  style: secondary,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MeasurementCard extends StatelessWidget {
  const _MeasurementCard({
    required this.measurement,
    required this.labels,
    required this.onTap,
  });

  final Measurement measurement;
  final Map<String, MetricInfo> labels;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(measurement.localTime),
    );
    return EvoCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${localizations.formatMediumDate(measurement.localTime)} · $time',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: EvoSpace.xs),
          Text(
            describeValues(measurement.values, labels),
            style: theme.textTheme.bodyMedium,
          ),
          if (measurement.notes case final notes?)
            Text(
              notes,
              style: theme.textTheme.labelSmall?.copyWith(
                color: EvoColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// Peso e medidas são dados de saúde: sem o consentimento, nada é registrado.
class _ConsentCard extends ConsumerStatefulWidget {
  const _ConsentCard();

  @override
  ConsumerState<_ConsentCard> createState() => _ConsentCardState();
}

class _ConsentCardState extends ConsumerState<_ConsentCard> {
  bool _saving = false;
  String? _error;

  Future<void> _grant() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(profileActionsProvider)
          .setConsent(ConsentKinds.healthData, granted: true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Autorize o uso de dados de saúde',
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: EvoSpace.sm),
          Text(
            'Peso e medidas do corpo são dados de saúde (LGPD). Para '
            'registrá-los, autorize o uso desses dados. Se desligar no perfil, '
            'as medidas registradas são apagadas.',
            style: theme.textTheme.bodyMedium,
          ),
          if (_error case final message?) ...[
            const SizedBox(height: EvoSpace.sm),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: EvoColors.danger,
              ),
            ),
          ],
          const SizedBox(height: EvoSpace.lg),
          EvoButton(
            label: 'Autorizar e continuar',
            isLoading: _saving,
            onPressed: _grant,
          ),
        ],
      ),
    );
  }
}
