import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_entrance.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../data/goals_api.dart';
import '../domain/goal.dart';
import 'goal_format.dart';

/// Primeiro passo de uma meta nova: escolher o tipo.
class NewGoalPage extends ConsumerWidget {
  const NewGoalPage({super.key});

  Future<void> _open(BuildContext context, GoalKind kind) async {
    // O formulário devolve true quando cria a meta: aí esta tela sai também,
    // e quem criou volta direto para a lista.
    final created = await context.push<bool>(
      AppRoutes.goalNewOfKind(kind.code),
    );
    if ((created ?? false) && context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(goalOptionsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Nova meta')),
      body: SafeArea(
        top: false,
        child: options.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoLoadingView(lines: 6),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(EvoSpace.xl),
              child: EvoErrorView(
                title: 'Não foi possível carregar os tipos de meta',
                message: error is ApiException
                    ? error.message
                    : 'Erro inesperado.',
                onRetry: () => ref.invalidate(goalOptionsProvider),
              ),
            ),
          ),
          data: (options) => ListView(
            padding: const EdgeInsets.all(EvoSpace.xl),
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Que tipo de meta?',
                  style: theme.textTheme.displaySmall,
                ),
              ),
              const SizedBox(height: EvoSpace.x2xl),
              for (final (i, kind) in options.kinds.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: EvoSpace.md),
                  child: EvoEntrance(
                    delay: EvoEntrance.stagger(i + 1),
                    child: _KindCard(
                      kind: kind,
                      onTap: () => _open(context, kind),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({required this.kind, required this.onTap});

  final GoalKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvoCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: EvoColors.bgElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(goalKindIcon(kind.code), size: 22),
          ),
          const SizedBox(width: EvoSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kind.label, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(kind.description, style: theme.textTheme.bodyMedium),
                if (kind.healthData) ...[
                  const SizedBox(height: EvoSpace.xs),
                  Row(
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: EvoColors.textSecondary,
                      ),
                      const SizedBox(width: EvoSpace.xs),
                      Flexible(
                        child: Text(
                          'Usa dado de saúde (peso)',
                          style: theme.textTheme.labelSmall,
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
