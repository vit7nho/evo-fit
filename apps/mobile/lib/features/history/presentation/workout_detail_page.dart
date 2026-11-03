import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../goals/presentation/goal_format.dart';
import '../../sessions/domain/session.dart';
import '../../sessions/domain/set_rows.dart';
import '../application/history_controller.dart';
import '../domain/history.dart';
import 'history_widgets.dart';

/// Um treino concluído: resumo, recordes batidos e cada exercício comparado com a
/// vez anterior.
class WorkoutDetailPage extends ConsumerWidget {
  const WorkoutDetailPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workout = ref.watch(workoutDetailProvider(sessionId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          workout.value?.name ?? 'Treino',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: workout.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoLoadingView(lines: 6),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(EvoSpace.xl),
              child: EvoErrorView(
                title: 'Não foi possível carregar o treino',
                message: error is ApiException
                    ? error.message
                    : 'Erro inesperado.',
                onRetry: () => ref.invalidate(workoutDetailProvider(sessionId)),
              ),
            ),
          ),
          data: (session) => _Detail(session: session),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = {
      for (final e in session.exercises) e.exercise.id: e.exercise.name,
    };
    final minutes = (session.elapsedS / 60).round();
    return ListView(
      padding: const EdgeInsets.all(EvoSpace.xl),
      children: [
        Text(
          formatGoalDate(context, session.startedAt.toLocal()),
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: EvoSpace.md),
        Wrap(
          spacing: EvoSpace.x2xl,
          runSpacing: EvoSpace.sm,
          children: [
            StatTile(label: 'Duração', value: '$minutes min'),
            StatTile(
              label: 'Volume',
              value: '${formatVolume(session.volumeKg)} kg',
            ),
            StatTile(label: 'Séries', value: '${session.setCount}'),
            if (session.perceivedEffort != null)
              StatTile(
                label: 'Esforço',
                value: '${session.perceivedEffort}/10',
              ),
          ],
        ),
        if (session.notes != null) ...[
          const SizedBox(height: EvoSpace.md),
          Text(session.notes!, style: theme.textTheme.bodyMedium),
        ],
        if (session.records.isNotEmpty) ...[
          const SizedBox(height: EvoSpace.xl),
          Semantics(
            header: true,
            child: Text(
              session.records.length == 1
                  ? '1 recorde neste treino'
                  : '${session.records.length} recordes neste treino',
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: EvoSpace.sm),
          for (final r in session.records)
            Padding(
              padding: const EdgeInsets.only(bottom: EvoSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.emoji_events_rounded, size: 20),
                  ),
                  const SizedBox(width: EvoSpace.sm),
                  Expanded(
                    child: Text(
                      '${names[r.exerciseId] ?? 'Exercício'} · '
                      '${RecordKind.label(r.kind)}: ${r.display} '
                      '(antes ${r.previousDisplay})',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: EvoSpace.xl),
        for (final entry in session.exercises)
          if (entry.sets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: EvoSpace.md),
              child: _ExerciseBlock(
                entry: entry,
                records: [
                  for (final r in session.records)
                    if (r.exerciseId == entry.exercise.id) r,
                ],
              ),
            ),
      ],
    );
  }
}

class _ExerciseBlock extends StatelessWidget {
  const _ExerciseBlock({required this.entry, required this.records});

  final SessionExercise entry;
  final List<RecordEvent> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Cada principal seguida dos segmentos dela, como na tela do treino.
    final ordered = [
      for (final main in entry.mainSets) ...[
        main,
        ...entry.segmentsOf(main.id),
      ],
    ];
    final kinds = [
      for (final s in ordered) RowKind.fromSet(s.kind, toFailure: s.toFailure),
    ];
    final badges = badgesFor(kinds);
    final comparison = compareWithPrevious(entry);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(EvoSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              label: '${entry.exercise.name}. Ver histórico e recordes.',
              excludeSemantics: true,
              child: InkWell(
                onTap: () =>
                    context.push(AppRoutes.exerciseHistory(entry.exercise.id)),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: evoTouchTargetMin,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.exercise.name,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            ),
            if (records.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: EvoSpace.sm),
                child: Wrap(
                  spacing: EvoSpace.xs,
                  runSpacing: EvoSpace.xs,
                  children: [
                    for (final r in records)
                      RecordBadge(label: RecordKind.label(r.kind)),
                  ],
                ),
              ),
            for (final (i, s) in ordered.indexed)
              HistorySetLine(
                badge: badges[i],
                kind: kinds[i],
                reps: s.reps,
                loadKg: s.loadKg,
                durationS: s.durationS,
                segment: s.isSegment,
              ),
            ..._comparison(context, comparison),
          ],
        ),
      ),
    );
  }

  /// "Volume: 800 kg (−280 kg)" e "Melhor série: 62,5 kg × 8 · 1RM est. 79,2 kg
  /// (antes 60 kg × 10, 80 kg)". Sem vez anterior, só o de hoje.
  List<Widget> _comparison(BuildContext context, ExerciseComparison c) {
    final theme = Theme.of(context);
    final lines = <String>[];
    if (c.volumeKg != null && c.volumeKg! > 0) {
      final delta = c.volumeDelta;
      final change = delta == null
          ? ''
          : delta == 0
          ? ' (igual à vez anterior)'
          : ' (${delta > 0 ? '+' : '−'}${formatVolume(delta.abs())} kg '
                'que a vez anterior)';
      lines.add('Volume: ${formatVolume(c.volumeKg!)} kg$change');
    }
    final best = c.best;
    if (best != null) {
      final before = c.previousBest;
      lines.add(
        'Melhor série: ${formatDecimal(best.loadKg)} kg × ${best.reps} · '
        '1RM est. ${formatDecimal(best.e1rm)} kg'
        '${before == null ? '' : ' (antes ${formatDecimal(before.loadKg)} kg × ${before.reps}, ${formatDecimal(before.e1rm)} kg)'}',
      );
    }
    if (lines.isEmpty) return const [];
    return [
      const SizedBox(height: EvoSpace.sm),
      const Divider(height: 1),
      const SizedBox(height: EvoSpace.sm),
      for (final line in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: EvoSpace.xs),
          child: Text(line, style: theme.textTheme.bodyMedium),
        ),
    ];
  }
}
