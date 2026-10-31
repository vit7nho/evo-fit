import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_entrance.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../application/goals_controller.dart';
import '../data/goals_api.dart';
import '../domain/goal.dart';
import 'goal_format.dart';

/// Lista de metas: ativas primeiro, depois as concluídas (alcançadas ou abandonadas).
class GoalsPage extends ConsumerWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    // Sem as opções, os cartões mostram só título e resumo; os rótulos chegam em seguida.
    final options = ref.watch(goalOptionsProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Metas')),
      body: SafeArea(
        top: false,
        child: goals.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoLoadingView(lines: 5),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(EvoSpace.xl),
              child: EvoErrorView(
                title: 'Não foi possível carregar suas metas',
                message: error is ApiException
                    ? error.message
                    : 'Erro inesperado.',
                onRetry: () => ref.invalidate(goalsProvider),
              ),
            ),
          ),
          data: (goals) => goals.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(EvoSpace.xl),
                    child: EvoEmptyView(
                      icon: Icons.flag_outlined,
                      title: 'Nenhuma meta ainda',
                      message:
                          'Defina o que quer alcançar: uma carga, uma distância, '
                          'treinar mais vezes por semana.',
                      actionLabel: 'Criar meta',
                      onAction: () => context.push(AppRoutes.goalNew),
                    ),
                  ),
                )
              : _GoalList(goals: goals, options: options),
        ),
      ),
    );
  }
}

class _GoalList extends StatelessWidget {
  const _GoalList({required this.goals, required this.options});

  final List<Goal> goals;
  final GoalOptions? options;

  @override
  Widget build(BuildContext context) {
    final active = goals.where((g) => g.isActive).toList();
    final closed = goals.where((g) => !g.isActive).toList();
    final today = DateTime.now();
    var index = 0;
    Widget card(Goal goal) => Padding(
      padding: const EdgeInsets.only(bottom: EvoSpace.md),
      child: EvoEntrance(
        delay: EvoEntrance.stagger(index++),
        child: _GoalCard(goal: goal, options: options, today: today),
      ),
    );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(EvoSpace.xl),
            children: [
              _SectionTitle(active.isEmpty ? 'Nenhuma meta ativa' : 'Ativas'),
              for (final goal in active) card(goal),
              if (closed.isNotEmpty) ...[
                const SizedBox(height: EvoSpace.lg),
                const _SectionTitle('Concluídas'),
                for (final goal in closed) card(goal),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            EvoSpace.xl,
            0,
            EvoSpace.xl,
            EvoSpace.lg,
          ),
          child: SizedBox(
            width: double.infinity,
            child: EvoButton(
              label: 'Nova meta',
              icon: Icons.add_rounded,
              onPressed: () => context.push(AppRoutes.goalNew),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EvoSpace.md),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.options,
    required this.today,
  });

  final Goal goal;
  final GoalOptions? options;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = goal.isOverdue(today);
    final deadline = goal.targetDate;
    final details = [
      ?options?.kind(goal.kind)?.label,
      if (!goal.isActive && options != null) options!.statusLabel(goal.status),
      if (goal.isActive && options != null)
        'Prioridade ${options!.priorityLabel(goal.priority).toLowerCase()}',
    ];

    return EvoCard(
      onTap: () => context.push(AppRoutes.goalEdit(goal.id)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: goal.isActive ? EvoColors.accent : EvoColors.bgElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(
              goal.status == GoalStatus.achieved
                  ? Icons.check_rounded
                  : goalKindIcon(goal.kind),
              color: goal.isActive
                  ? EvoColors.onAccent
                  : EvoColors.textSecondary,
              size: 22,
            ),
          ),
          const SizedBox(width: EvoSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(goal.title, style: theme.textTheme.titleMedium),
                if (goal.summary.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(goal.summary, style: theme.textTheme.bodyMedium),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: EvoSpace.xs),
                  Text(details.join(' · '), style: theme.textTheme.labelSmall),
                ],
                if (deadline != null && goal.isActive) ...[
                  const SizedBox(height: EvoSpace.xs),
                  // Vencida: ícone e texto, não só a cor.
                  Row(
                    children: [
                      Icon(
                        overdue
                            ? Icons.warning_amber_rounded
                            : Icons.event_outlined,
                        size: 16,
                        color: overdue
                            ? EvoColors.warning
                            : EvoColors.textSecondary,
                      ),
                      const SizedBox(width: EvoSpace.xs),
                      Flexible(
                        child: Text(
                          overdue
                              ? 'Prazo vencido em ${formatGoalDate(context, deadline)}'
                              : 'Até ${formatGoalDate(context, deadline)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: overdue
                                ? EvoColors.warning
                                : EvoColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: EvoSpace.sm),
          const Icon(
            Icons.chevron_right_rounded,
            color: EvoColors.textSecondary,
          ),
        ],
      ),
    );
  }
}
