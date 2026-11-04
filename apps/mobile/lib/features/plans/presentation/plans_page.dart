import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_entrance.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../application/plans_controller.dart';
import '../domain/plan.dart';
import 'plan_widgets.dart';

/// Planos de caminhada, 5 km e 10 km: o em andamento, os oferecidos e os anteriores.
class PlansPage extends ConsumerWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Planos')),
      body: SafeArea(
        top: false,
        child: plans.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoLoadingView(lines: 4),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(EvoSpace.xl),
              child: EvoErrorView(
                title: 'Não foi possível carregar seus planos',
                message: error is ApiException
                    ? error.message
                    : 'Erro inesperado.',
                onRetry: () => ref.invalidate(plansProvider),
              ),
            ),
          ),
          data: (list) {
            final active = list.where((p) => p.active).firstOrNull;
            final past = list.where((p) => !p.active).toList();
            return ListView(
              padding: const EdgeInsets.all(EvoSpace.xl),
              children: [
                if (active != null) ...[
                  Semantics(
                    header: true,
                    child: Text(
                      'Em andamento',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: EvoSpace.md),
                  EvoEntrance(child: _ActivePlanCard(plan: active)),
                ] else
                  const _Offers(),
                if (past.isNotEmpty) ...[
                  const SizedBox(height: EvoSpace.x2xl),
                  Semantics(
                    header: true,
                    child: Text(
                      'Planos anteriores',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: EvoSpace.md),
                  for (final plan in past)
                    Padding(
                      padding: const EdgeInsets.only(bottom: EvoSpace.md),
                      child: _PastPlanCard(plan: plan),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActivePlanCard extends StatelessWidget {
  const _ActivePlanCard({required this.plan});

  final TrainingPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvoCard(
      onTap: () => context.push(AppRoutes.plan(plan.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlanIcon(modality: plan.modality),
              const SizedBox(width: EvoSpace.lg),
              Expanded(
                child: Text(plan.title, style: theme.textTheme.titleMedium),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: EvoColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: EvoSpace.lg),
          PlanProgress(plan: plan),
        ],
      ),
    );
  }
}

class _PastPlanCard extends StatelessWidget {
  const _PastPlanCard({required this.plan});

  final TrainingPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = plan.status == PlanStatuses.completed
        ? 'Concluído'
        : 'Encerrado';
    return EvoCard(
      onTap: () => context.push(AppRoutes.plan(plan.id)),
      child: Row(
        children: [
          PlanIcon(modality: plan.modality, muted: true),
          const SizedBox(width: EvoSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '$status · ${plan.completedSessions} de '
                  '${plan.totalSessions} sessões',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: EvoColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Os planos para começar, já com os ajustes e avisos para a pessoa.
class _Offers extends ConsumerWidget {
  const _Offers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(planTemplatesProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Escolha um plano', style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: EvoSpace.xs),
        Text(
          'Três sessões por semana, nos dias que você escolher. Cada sessão '
          'feita é marcada com a atividade que você registrar.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: EvoSpace.lg),
        ...templates.when(
          loading: () => const [EvoLoadingView(lines: 3)],
          error: (error, _) => [
            EvoErrorView(
              title: 'Não foi possível carregar os planos',
              message: error is ApiException
                  ? error.message
                  : 'Erro inesperado.',
              onRetry: () => ref.invalidate(planTemplatesProvider),
            ),
          ],
          data: (list) => [
            for (final (index, template) in list.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: EvoSpace.md),
                child: EvoEntrance(
                  delay: EvoEntrance.stagger(index),
                  child: _OfferCard(template: template),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.template});

  final PlanTemplate template;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvoCard(
      onTap: () => context.push(AppRoutes.planNew(template.kind)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlanIcon(modality: template.modality),
          const SizedBox(width: EvoSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '${template.weeks} semanas · ${template.summary}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (template.note case final note?) ...[
                  const SizedBox(height: EvoSpace.sm),
                  Text(
                    note,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: EvoColors.warning,
                    ),
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
