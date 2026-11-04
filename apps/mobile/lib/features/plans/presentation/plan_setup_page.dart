import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_form_error.dart';
import '../../../shared/widgets/evo_selection.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../goals/presentation/goal_format.dart';
import '../application/plans_controller.dart';
import '../domain/plan.dart';
import 'plan_widgets.dart';

/// Começar um plano: os dias da semana e quando começa.
class PlanSetupPage extends ConsumerWidget {
  const PlanSetupPage({super.key, required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(planTemplatesProvider);
    return templates.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.all(EvoSpace.xl),
          child: EvoLoadingView(lines: 5),
        ),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(EvoSpace.xl),
            child: EvoErrorView(
              title: 'Não foi possível carregar o plano',
              message: error is ApiException
                  ? error.message
                  : 'Erro inesperado.',
              onRetry: () => ref.invalidate(planTemplatesProvider),
            ),
          ),
        ),
      ),
      data: (list) {
        final template = list.where((t) => t.kind == kind).firstOrNull;
        if (template == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(EvoSpace.xl),
                child: EvoErrorView(
                  title: 'Plano não encontrado',
                  message: 'Volte e escolha um dos planos da lista.',
                ),
              ),
            ),
          );
        }
        return _PlanSetup(template: template);
      },
    );
  }
}

class _PlanSetup extends ConsumerStatefulWidget {
  const _PlanSetup({required this.template});

  final PlanTemplate template;

  @override
  ConsumerState<_PlanSetup> createState() => _PlanSetupState();
}

class _PlanSetupState extends ConsumerState<_PlanSetup> {
  // Segunda, quarta e sexta: valem para todos os planos.
  Set<int> _days = {0, 2, 4};
  late DateTime _start = _today;
  bool _saving = false;
  ApiException? _error;

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String? get _daysProblem =>
      checkPlanWeekdays(_days, runs: widget.template.runs);

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 28)),
      helpText: 'Começar em',
    );
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _begin() async {
    if (_saving || _daysProblem != null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final plan = await ref
          .read(plansProvider.notifier)
          .start(
            kind: widget.template.kind,
            weekdays: _days.toList()..sort(),
            startDate: _start,
          );
      if (!mounted) return;
      // Troca a configuração pelo plano novo: voltar leva a Planos.
      context.pushReplacement(AppRoutes.plan(plan.id));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final template = widget.template;
    final problem = _daysProblem;
    final tomorrow = _today.add(const Duration(days: 1));
    final custom = _start != _today && _start != tomorrow;

    return Scaffold(
      appBar: AppBar(title: Text(template.title)),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(EvoSpace.xl),
                children: [
                  Row(
                    children: [
                      PlanIcon(modality: template.modality),
                      const SizedBox(width: EvoSpace.lg),
                      Expanded(
                        child: Text(
                          template.summary,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: EvoSpace.lg),
                  Text(
                    '${template.weeks} semanas · '
                    '${template.sessionsPerWeek} sessões por semana',
                    style: theme.textTheme.titleSmall,
                  ),
                  if (template.prerequisite case final text?) ...[
                    const SizedBox(height: EvoSpace.sm),
                    Text(text, style: theme.textTheme.bodyMedium),
                  ],
                  if (template.note case final note?) ...[
                    const SizedBox(height: EvoSpace.lg),
                    _Notice(
                      icon: Icons.info_outline_rounded,
                      color: EvoColors.warning,
                      text: note,
                    ),
                  ],
                  for (final text in template.adaptations) ...[
                    const SizedBox(height: EvoSpace.lg),
                    _Notice(
                      icon: Icons.tune_rounded,
                      color: EvoColors.textPrimary,
                      text: text,
                    ),
                  ],
                  const SizedBox(height: EvoSpace.xl),
                  const EvoFieldLabel('Dias da semana (escolha 3)'),
                  Wrap(
                    spacing: EvoSpace.sm,
                    runSpacing: EvoSpace.sm,
                    children: [
                      for (var day = 0; day < 7; day++)
                        Semantics(
                          label: weekdayLong[day],
                          child: EvoChip(
                            label: weekdayShort[day],
                            selected: _days.contains(day),
                            onTap: () => setState(() {
                              _error = null;
                              _days = _days.contains(day)
                                  ? ({..._days}..remove(day))
                                  : {..._days, day};
                            }),
                          ),
                        ),
                    ],
                  ),
                  if (problem != null) ...[
                    const SizedBox(height: EvoSpace.sm),
                    Text(
                      problem,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: EvoColors.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: EvoSpace.xl),
                  const EvoFieldLabel('Começar'),
                  Wrap(
                    spacing: EvoSpace.sm,
                    runSpacing: EvoSpace.sm,
                    children: [
                      EvoChip(
                        label: 'Hoje',
                        selected: _start == _today,
                        onTap: () => setState(() => _start = _today),
                      ),
                      EvoChip(
                        label: 'Amanhã',
                        selected: _start == tomorrow,
                        onTap: () => setState(() => _start = tomorrow),
                      ),
                      EvoChip(
                        label: custom
                            ? formatGoalDate(context, _start)
                            : 'Outro dia',
                        selected: custom,
                        onTap: _pickStart,
                      ),
                    ],
                  ),
                  const SizedBox(height: EvoSpace.xl),
                  Text(
                    'As datas são sugestões: se perder um dia, siga da próxima '
                    'sessão. Sentiu dor, tontura ou falta de ar? Pare e procure '
                    'orientação.',
                    style: theme.textTheme.bodySmall,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EvoFormError(message: _error?.message),
                  EvoButton(
                    label: 'Começar plano',
                    isLoading: _saving,
                    onPressed: problem == null ? _begin : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(EvoSpace.md),
      decoration: BoxDecoration(
        color: EvoColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: EvoSpace.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
