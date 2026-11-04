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
import '../../goals/presentation/goal_format.dart';
import '../../history/domain/history.dart' show Paged;
import '../application/activities_controller.dart';
import '../data/activities_api.dart';
import '../domain/activity.dart';

/// Corridas, caminhadas, pedais e nados, da mais recente.
class ActivitiesPage extends ConsumerStatefulWidget {
  const ActivitiesPage({super.key});

  @override
  ConsumerState<ActivitiesPage> createState() => _ActivitiesPageState();
}

class _ActivitiesPageState extends ConsumerState<ActivitiesPage> {
  bool _loadingMore = false;

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      await ref.read(activitiesProvider.notifier).loadMore();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activities = ref.watch(activitiesProvider);
    // Sem as opções, os cartões usam o ícone e o código; os rótulos chegam em seguida.
    final options = ref.watch(activityOptionsProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Atividades'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push(AppRoutes.plans),
            icon: const Icon(Icons.flag_circle_outlined),
            label: const Text('Planos'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: activities.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoLoadingView(lines: 5),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(EvoSpace.xl),
              child: EvoErrorView(
                title: 'Não foi possível carregar suas atividades',
                message: error is ApiException
                    ? error.message
                    : 'Erro inesperado.',
                onRetry: () => ref.invalidate(activitiesProvider),
              ),
            ),
          ),
          data: (page) => page.items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(EvoSpace.xl),
                    child: EvoEmptyView(
                      icon: Icons.directions_run_rounded,
                      title: 'Nenhuma atividade ainda',
                      message:
                          'Registre corridas, caminhadas, pedais e nados: '
                          'duração, distância e como foi.',
                      actionLabel: 'Registrar atividade',
                      onAction: () => context.push(AppRoutes.activityNew),
                    ),
                  ),
                )
              : _ActivityList(
                  page: page,
                  options: options,
                  loadingMore: _loadingMore,
                  onLoadMore: _loadMore,
                ),
        ),
      ),
    );
  }
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({
    required this.page,
    required this.options,
    required this.loadingMore,
    required this.onLoadMore,
  });

  final Paged<Activity> page;
  final ActivityOptions? options;
  final bool loadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(EvoSpace.xl),
            children: [
              for (final (index, activity) in page.items.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: EvoSpace.md),
                  child: EvoEntrance(
                    delay: EvoEntrance.stagger(index),
                    child: _ActivityCard(activity: activity, options: options),
                  ),
                ),
              if (page.nextBefore != null)
                EvoButton(
                  label: 'Carregar mais',
                  variant: EvoButtonVariant.secondary,
                  isLoading: loadingMore,
                  onPressed: onLoadMore,
                ),
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
              label: 'Registrar atividade',
              icon: Icons.add_rounded,
              onPressed: () => context.push(AppRoutes.activityNew),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity, required this.options});

  final Activity activity;
  final ActivityOptions? options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final when = activity.startedAt;
    final details = [
      formatDuration(activity.durationS),
      if (activity.distanceM case final meters?)
        formatDistance(meters, modality: activity.modality),
      ?activity.rhythm,
      if (activity.perceivedEffort case final effort?) 'esforço $effort/10',
    ];

    return EvoCard(
      onTap: () => context.push(AppRoutes.activityEdit(activity.id)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: EvoColors.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              modalityIcon(activity.modality),
              color: EvoColors.onAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: EvoSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  options?.modalityLabel(activity.modality) ??
                      activity.modality,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(details.join(' · '), style: theme.textTheme.bodyMedium),
                const SizedBox(height: EvoSpace.xs),
                Text(
                  '${formatGoalDate(context, when)} · '
                  '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(when))}',
                  style: theme.textTheme.labelSmall,
                ),
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
