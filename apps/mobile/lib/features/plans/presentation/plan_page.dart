import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../activities/application/activities_controller.dart';
import '../../activities/domain/activity.dart';
import '../../activities/presentation/activity_form_page.dart';
import '../../goals/presentation/goal_format.dart';
import '../application/plans_controller.dart';
import '../domain/plan.dart';
import 'plan_widgets.dart';

/// Um plano: progresso, a próxima sessão e todas as sessões por semana.
class PlanPage extends ConsumerWidget {
  const PlanPage({super.key, required this.planId});

  final String planId;

  Future<void> _end(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encerrar o plano?'),
        content: const Text(
          'As sessões feitas e as atividades continuam no histórico. Depois '
          'você pode começar outro plano.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuar no plano'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(planProvider(planId).notifier).end();
      messenger.showSnackBar(const SnackBar(content: Text('Plano encerrado')));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider(planId));
    final active = plan.value?.active ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(plan.value?.title ?? 'Plano'),
        actions: [
          if (active)
            PopupMenuButton<String>(
              tooltip: 'Mais opções',
              onSelected: (_) => _end(context, ref),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'end', child: Text('Encerrar plano')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: plan.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoLoadingView(lines: 6),
          ),
          error: (error, _) {
            final notFound = error is ApiException && error.statusCode == 404;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(EvoSpace.xl),
                child: EvoErrorView(
                  title: notFound
                      ? 'Plano não encontrado'
                      : 'Não foi possível carregar o plano',
                  message: error is ApiException
                      ? error.message
                      : 'Erro inesperado.',
                  onRetry: notFound
                      ? null
                      : () => ref.invalidate(planProvider(planId)),
                ),
              ),
            );
          },
          data: (plan) => _PlanBody(plan: plan),
        ),
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.plan});

  final TrainingPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = plan.nextSession;
    final weeks = <int, List<PlanSession>>{};
    for (final session in plan.sessions) {
      (weeks[session.week] ??= []).add(session);
    }
    final status = switch (plan.status) {
      PlanStatuses.completed => 'Plano concluído. Parabéns!',
      PlanStatuses.ended => 'Plano encerrado.',
      _ => null,
    };

    return ListView(
      padding: const EdgeInsets.all(EvoSpace.xl),
      children: [
        PlanProgress(plan: plan),
        if (status != null) ...[
          const SizedBox(height: EvoSpace.md),
          Text(status, style: theme.textTheme.titleMedium),
        ],
        for (final text in plan.adaptations) ...[
          const SizedBox(height: EvoSpace.md),
          Text(text, style: theme.textTheme.bodySmall),
        ],
        if (next != null) ...[
          const SizedBox(height: EvoSpace.xl),
          Semantics(
            header: true,
            child: Text('Próxima sessão', style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: EvoSpace.md),
          _NextSessionCard(plan: plan, session: next),
        ],
        for (final MapEntry(key: week, value: sessions) in weeks.entries) ...[
          const SizedBox(height: EvoSpace.xl),
          Semantics(
            header: true,
            child: Text('Semana $week', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: EvoSpace.sm),
          for (final session in sessions)
            _SessionTile(
              plan: plan,
              session: session,
              isNext: session.id == next?.id,
            ),
        ],
      ],
    );
  }
}

class _NextSessionCard extends StatelessWidget {
  const _NextSessionCard({required this.plan, required this.session});

  final TrainingPlan plan;
  final PlanSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Semana ${session.week}, sessão ${session.dayIndex} · '
            '${formatPlannedDuration(session.totalS)}',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: EvoSpace.sm),
          Text(session.summary, style: theme.textTheme.titleMedium),
          const SizedBox(height: EvoSpace.lg),
          EvoButton(
            label: 'Registrar sessão',
            icon: Icons.add_rounded,
            onPressed: () =>
                context.push(AppRoutes.planSessionLog(plan.id, session.id)),
          ),
          const SizedBox(height: EvoSpace.sm),
          EvoButton(
            label: 'Usar atividade já registrada',
            variant: EvoButtonVariant.secondary,
            onPressed: () => pickActivityForSession(context, plan, session),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.plan,
    required this.session,
    required this.isNext,
  });

  final TrainingPlan plan;
  final PlanSession session;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = session.done
        ? 'feita'
        : isNext
        ? 'próxima'
        : 'pendente';
    return Semantics(
      label:
          'Sessão ${session.dayIndex}, $state. ${session.summary}. '
          '${formatPlannedDuration(session.totalS)}',
      excludeSemantics: true,
      button: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: () => _showSession(context, plan, session),
        leading: Icon(
          session.done
              ? Icons.check_circle_rounded
              : isNext
              ? Icons.play_circle_outline_rounded
              : Icons.radio_button_unchecked_rounded,
          color: session.done ? EvoColors.success : EvoColors.textSecondary,
        ),
        title: Text(
          session.summary,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isNext ? FontWeight.w600 : null,
          ),
        ),
        subtitle: Text(
          '${formatSessionDate(context, session.scheduledDate)} · '
          '${formatPlannedDuration(session.totalS)}',
          style: theme.textTheme.labelSmall,
        ),
      ),
    );
  }
}

Future<void> _showSession(
  BuildContext context,
  TrainingPlan plan,
  PlanSession session,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => _SessionSheet(plan: plan, session: session),
);

class _SessionSheet extends ConsumerStatefulWidget {
  const _SessionSheet({required this.plan, required this.session});

  final TrainingPlan plan;
  final PlanSession session;

  @override
  ConsumerState<_SessionSheet> createState() => _SessionSheetState();
}

class _SessionSheetState extends ConsumerState<_SessionSheet> {
  bool _busy = false;

  Future<void> _undo() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(planProvider(widget.plan.id).notifier)
          .unlink(widget.session.id);
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Sessão desmarcada')),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = widget.plan;
    final session = widget.session;
    // Rola com fonte grande: o resumo da sessão pode ser longo.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          EvoSpace.xl,
          0,
          EvoSpace.xl,
          EvoSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Semana ${session.week}, sessão ${session.dayIndex}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: EvoSpace.xs),
            Text(
              'Sugestão: ${formatSessionDate(context, session.scheduledDate)} · '
              '${formatPlannedDuration(session.totalS)}',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: EvoSpace.lg),
            Text(session.summary, style: theme.textTheme.bodyLarge),
            const SizedBox(height: EvoSpace.xl),
            if (session.done) ...[
              EvoButton(
                label: 'Ver atividade',
                variant: EvoButtonVariant.secondary,
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(
                    AppRoutes.activityEdit(session.completedActivityId!),
                  );
                },
              ),
              if (plan.active) ...[
                const SizedBox(height: EvoSpace.sm),
                EvoButton(
                  label: 'Desmarcar sessão',
                  variant: EvoButtonVariant.secondary,
                  isLoading: _busy,
                  onPressed: _undo,
                ),
              ],
            ] else if (plan.active) ...[
              EvoButton(
                label: 'Registrar sessão',
                icon: Icons.add_rounded,
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(AppRoutes.planSessionLog(plan.id, session.id));
                },
              ),
              const SizedBox(height: EvoSpace.sm),
              EvoButton(
                label: 'Usar atividade já registrada',
                variant: EvoButtonVariant.secondary,
                onPressed: () {
                  Navigator.of(context).pop();
                  pickActivityForSession(context, plan, session);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Modalidades que contam para as sessões do plano (como a API).
List<String> planModalities(TrainingPlan plan) => plan.modality == 'walk'
    ? const [Modalities.walk, Modalities.run]
    : const [Modalities.run];

/// Escolher, entre as atividades já registradas, a que vale para a sessão.
Future<void> pickActivityForSession(
  BuildContext context,
  TrainingPlan plan,
  PlanSession session,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => _ActivityPicker(plan: plan, session: session),
);

class _ActivityPicker extends ConsumerStatefulWidget {
  const _ActivityPicker({required this.plan, required this.session});

  final TrainingPlan plan;
  final PlanSession session;

  @override
  ConsumerState<_ActivityPicker> createState() => _ActivityPickerState();
}

class _ActivityPickerState extends ConsumerState<_ActivityPicker> {
  String? _linking;

  Future<void> _pick(Activity activity) async {
    setState(() => _linking = activity.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(planProvider(widget.plan.id).notifier)
          .link(widget.session.id, activity.id);
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Sessão concluída. Bom trabalho!')),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.fieldErrors['activity_id'] ?? error.message),
        ),
      );
      if (mounted) setState(() => _linking = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = widget.plan;
    final used = {for (final s in plan.sessions) ?s.completedActivityId};
    final modalities = planModalities(plan);
    final activities = ref.watch(activitiesProvider);

    final List<Widget> content = activities.when(
      loading: () => const [EvoLoadingView(lines: 3)],
      error: (error, _) => [
        Text(error is ApiException ? error.message : 'Erro inesperado.'),
      ],
      data: (page) {
        final options = page.items
            .where(
              (a) =>
                  modalities.contains(a.modality) &&
                  !used.contains(a.id) &&
                  !_dayOf(a.startedAt).isBefore(plan.startDate),
            )
            .toList();
        if (options.isEmpty) {
          return [
            Text(
              plan.modality == 'walk'
                  ? 'Nenhuma caminhada ou corrida registrada desde o início '
                        'do plano.'
                  : 'Nenhuma corrida registrada desde o início do plano.',
              style: theme.textTheme.bodyMedium,
            ),
          ];
        }
        return [
          for (final activity in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: _linking == null,
              leading: Icon(modalityIcon(activity.modality)),
              title: Text(
                [
                  formatDuration(activity.durationS),
                  if (activity.distanceM case final m?)
                    formatDistance(m, modality: activity.modality),
                ].join(' · '),
              ),
              subtitle: Text(formatGoalDate(context, activity.startedAt)),
              trailing: _linking == activity.id
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: () => _pick(activity),
            ),
        ];
      },
    );

    // Uma só área de rolagem: com fonte grande, até o título pode ocupar a tela.
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            EvoSpace.xl,
            0,
            EvoSpace.xl,
            EvoSpace.xl,
          ),
          children: [
            Text(
              'Qual atividade foi esta sessão?',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: EvoSpace.md),
            ...content,
          ],
        ),
      ),
    );
  }

  static DateTime _dayOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);
}

/// Registrar a sessão pelo formulário de atividade, já preenchido.
class PlanSessionLogPage extends ConsumerWidget {
  const PlanSessionLogPage({
    super.key,
    required this.planId,
    required this.sessionId,
  });

  final String planId;
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider(planId));
    final session = plan.value?.sessions
        .where((s) => s.id == sessionId)
        .firstOrNull;
    if (plan.hasError || (plan.hasValue && session == null)) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoErrorView(
              title: 'Sessão não encontrada',
              message: 'Volte para o plano e tente de novo.',
            ),
          ),
        ),
      );
    }
    if (session == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.all(EvoSpace.xl),
          child: EvoLoadingView(lines: 6),
        ),
      );
    }
    final loaded = plan.requireValue;
    return ActivityFormPage.create(
      planSession: PlanSessionTarget(
        planId: planId,
        sessionId: sessionId,
        label:
            '${loaded.title} · semana ${session.week}, '
            'sessão ${session.dayIndex}',
        modalities: planModalities(loaded),
        durationS: session.totalS,
      ),
    );
  }
}
