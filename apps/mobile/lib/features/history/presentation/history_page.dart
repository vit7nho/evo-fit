import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../goals/presentation/goal_format.dart';
import '../application/history_controller.dart';
import '../domain/history.dart';
import 'history_widgets.dart';

/// Histórico: os treinos concluídos e os recordes por exercício, em duas abas.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Histórico'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Treinos'),
              Tab(text: 'Recordes'),
            ],
          ),
        ),
        body: const SafeArea(
          top: false,
          child: TabBarView(children: [_SessionsTab(), _RecordsTab()]),
        ),
      ),
    );
  }
}

Widget _error(Object error, VoidCallback onRetry, String title) => Center(
  child: SingleChildScrollView(
    padding: const EdgeInsets.all(EvoSpace.xl),
    child: EvoErrorView(
      title: title,
      message: error is ApiException ? error.message : 'Erro inesperado.',
      onRetry: onRetry,
    ),
  ),
);

class _SessionsTab extends ConsumerStatefulWidget {
  const _SessionsTab();

  @override
  ConsumerState<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends ConsumerState<_SessionsTab> {
  bool _loadingMore = false;

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(sessionHistoryProvider.notifier).loadMore();
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(sessionHistoryProvider);
    return history.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(EvoSpace.xl),
        child: EvoLoadingView(lines: 5),
      ),
      error: (error, _) => _error(
        error,
        () => ref.invalidate(sessionHistoryProvider),
        'Não foi possível carregar o histórico',
      ),
      data: (page) => page.items.isEmpty
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(EvoSpace.xl),
                child: EvoEmptyView(
                  icon: Icons.history_rounded,
                  title: 'Nenhum treino concluído ainda',
                  message:
                      'Quando você finalizar um treino, ele aparece aqui com '
                      'as séries, o volume e os recordes.',
                  actionLabel: 'Ver fichas',
                  onAction: () => context.push(AppRoutes.templates),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(sessionHistoryProvider.future),
              child: ListView(
                padding: const EdgeInsets.all(EvoSpace.xl),
                children: [
                  for (final session in page.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: EvoSpace.md),
                      child: _SessionCard(session: session),
                    ),
                  if (page.nextBefore != null)
                    EvoButton(
                      label: 'Carregar mais',
                      variant: EvoButtonVariant.secondary,
                      isLoading: _loadingMore,
                      onPressed: _loadMore,
                    ),
                ],
              ),
            ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = session.durationS == null
        ? null
        : (session.durationS! / 60).round();
    final details = [
      ?(minutes == null ? null : '$minutes min'),
      session.setCount == 1 ? '1 série' : '${session.setCount} séries',
      if (session.volumeKg > 0) '${formatVolume(session.volumeKg)} kg',
    ].join(' · ');
    final more = session.exerciseCount - session.exerciseNames.length;
    return EvoCard(
      onTap: () => context.push(AppRoutes.workoutDetail(session.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatGoalDate(context, session.startedAt),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 2),
          Text(session.name, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(details, style: theme.textTheme.bodyMedium),
          if (session.exerciseNames.isNotEmpty) ...[
            const SizedBox(height: EvoSpace.xs),
            Text(
              [...session.exerciseNames, if (more > 0) '+$more'].join(', '),
              style: theme.textTheme.labelSmall,
            ),
          ],
          if (session.recordCount > 0) ...[
            const SizedBox(height: EvoSpace.sm),
            RecordBadge(
              label: session.recordCount == 1
                  ? '1 recorde'
                  : '${session.recordCount} recordes',
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordsTab extends ConsumerWidget {
  const _RecordsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(recordsProvider);
    final theme = Theme.of(context);
    return records.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(EvoSpace.xl),
        child: EvoLoadingView(lines: 5),
      ),
      error: (error, _) => _error(
        error,
        () => ref.invalidate(recordsProvider),
        'Não foi possível carregar os recordes',
      ),
      data: (list) => list.isEmpty
          ? const Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(EvoSpace.xl),
                child: EvoEmptyView(
                  icon: Icons.emoji_events_outlined,
                  title: 'Ainda não há recordes',
                  message:
                      'Os recordes aparecem depois do primeiro treino concluído '
                      'e são superados a cada evolução.',
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(EvoSpace.xl),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: EvoSpace.md),
                  child: Text(
                    'O 1RM é uma estimativa (fórmula de Epley), não um teste de carga máxima.',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                for (final item in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: EvoSpace.md),
                    child: EvoCard(
                      onTap: () => context.push(
                        AppRoutes.exerciseHistory(item.exercise.id),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.exercise.name,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: EvoSpace.sm),
                          Wrap(
                            spacing: EvoSpace.xl,
                            runSpacing: EvoSpace.sm,
                            children: [
                              for (final r in item.records)
                                StatTile(
                                  label: RecordKind.label(r.kind),
                                  value: r.display,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
