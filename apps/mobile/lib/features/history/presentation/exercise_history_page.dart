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
import '../../goals/presentation/goal_format.dart';
import '../../sessions/domain/set_rows.dart';
import '../application/history_controller.dart';
import '../domain/history.dart';
import 'history_widgets.dart';

/// Histórico de um exercício: recordes, recordes por repetições e cada treino.
class ExerciseHistoryPage extends ConsumerStatefulWidget {
  const ExerciseHistoryPage({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  ConsumerState<ExerciseHistoryPage> createState() =>
      _ExerciseHistoryPageState();
}

class _ExerciseHistoryPageState extends ConsumerState<ExerciseHistoryPage> {
  bool _loadingMore = false;

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(exerciseHistoryProvider(widget.exerciseId).notifier)
          .loadMore();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(exerciseHistoryProvider(widget.exerciseId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          history.value?.exercise.name ?? 'Histórico',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: history.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoLoadingView(lines: 6),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(EvoSpace.xl),
              child: EvoErrorView(
                title: 'Não foi possível carregar o histórico',
                message: error is ApiException
                    ? error.message
                    : 'Erro inesperado.',
                onRetry: () =>
                    ref.invalidate(exerciseHistoryProvider(widget.exerciseId)),
              ),
            ),
          ),
          data: (data) => data.sessions.isEmpty
              ? const Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(EvoSpace.xl),
                    child: EvoEmptyView(
                      icon: Icons.history_rounded,
                      title: 'Ainda não há registros',
                      message:
                          'Quando você concluir um treino com este exercício, '
                          'as séries e os recordes aparecem aqui.',
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(EvoSpace.xl),
                  children: [
                    if (data.records.isNotEmpty) ...[
                      _Header('Recordes'),
                      Wrap(
                        spacing: EvoSpace.x2xl,
                        runSpacing: EvoSpace.md,
                        children: [
                          for (final r in data.records)
                            StatTile(
                              label: RecordKind.label(r.kind),
                              value:
                                  '${r.display} · ${formatGoalDate(context, r.achievedAt)}',
                            ),
                        ],
                      ),
                      if (data.records.any(
                        (r) => r.kind == RecordKind.bestE1rm,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(top: EvoSpace.sm),
                          child: Text(
                            'O 1RM é uma estimativa (fórmula de Epley), não um teste de carga máxima.',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      const SizedBox(height: EvoSpace.xl),
                    ],
                    if (_e1rmPoints(context, data.sessions) case final points
                        when points.length > 1) ...[
                      _Header('1RM estimado por treino'),
                      EvoLineChart(
                        key: const ValueKey('e1rm-chart'),
                        title: '1RM estimado por treino',
                        points: points,
                        format: (v) => '${formatDecimal(v)} kg',
                        axisFormat: (v) => formatDecimal(v),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: EvoSpace.sm),
                        child: Text(
                          data.nextBefore == null
                              ? 'Todos os treinos com carga.'
                              : 'Os treinos carregados abaixo; “Carregar mais” '
                                    'estende o gráfico.',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      const SizedBox(height: EvoSpace.xl),
                    ],
                    if (data.repRecords.isNotEmpty) ...[
                      _Header('Melhor carga por repetições'),
                      for (final r in data.repRecords)
                        Semantics(
                          container: true,
                          label:
                              '${r.reps} repetições: ${formatDecimal(r.value)} kg, '
                              '${formatGoalDate(context, r.achievedAt)}',
                          excludeSemantics: true,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: EvoSpace.xs),
                            // Com fonte grande, a data desce para a linha de baixo.
                            child: Wrap(
                              spacing: EvoSpace.md,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: 64,
                                  ),
                                  child: Text(
                                    '${r.reps} rep.',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                Text(
                                  '${formatDecimal(r.value)} kg',
                                  style: theme.textTheme.bodyLarge,
                                ),
                                Text(
                                  formatGoalDate(context, r.achievedAt),
                                  style: theme.textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: EvoSpace.xl),
                    ],
                    _Header('Treinos'),
                    for (final s in data.sessions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: EvoSpace.md),
                        child: _SessionBlock(session: s),
                      ),
                    if (data.nextBefore != null)
                      EvoButton(
                        label: 'Carregar mais',
                        variant: EvoButtonVariant.secondary,
                        isLoading: _loadingMore,
                        onPressed: _loadMore,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Um ponto por treino com carga, do mais antigo ao mais recente (3.7).
List<ChartPoint> _e1rmPoints(
  BuildContext context,
  List<ExerciseSession> sessions,
) => [
  for (final s in sessions.reversed)
    if (s.bestE1rm case final e1rm?)
      ChartPoint(
        label: axisDate(s.startedAt.toLocal()),
        spoken: formatGoalDate(context, s.startedAt.toLocal()),
        value: e1rm,
      ),
];

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: EvoSpace.sm),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

class _SessionBlock extends StatelessWidget {
  const _SessionBlock({required this.session});

  final ExerciseSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kinds = [
      for (final s in session.sets)
        RowKind.fromSet(s.kind, toFailure: s.toFailure),
    ];
    final badges = badgesFor(kinds);
    final summary = [
      if (session.volumeKg > 0) '${formatVolume(session.volumeKg)} kg',
      if (session.bestE1rm != null)
        '1RM est. ${formatDecimal(session.bestE1rm!)} kg',
    ].join(' · ');
    return EvoCard(
      onTap: () => context.push(AppRoutes.workoutDetail(session.sessionId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatGoalDate(context, session.startedAt)} · ${session.sessionName}',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: EvoSpace.sm),
          for (final (i, s) in session.sets.indexed)
            HistorySetLine(
              badge: badges[i],
              kind: kinds[i],
              reps: s.reps,
              loadKg: s.loadKg,
              durationS: s.durationS,
              segment: s.isSegment,
            ),
          if (summary.isNotEmpty)
            Text(summary, style: theme.textTheme.bodyMedium),
          if (session.records.isNotEmpty) ...[
            const SizedBox(height: EvoSpace.sm),
            Wrap(
              spacing: EvoSpace.xs,
              runSpacing: EvoSpace.xs,
              children: [
                for (final kind in session.records)
                  RecordBadge(label: RecordKind.label(kind)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
