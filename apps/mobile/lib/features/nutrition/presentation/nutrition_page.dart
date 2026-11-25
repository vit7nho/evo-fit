import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../profile/application/profile_actions.dart';
import '../../profile/domain/profile.dart' show ConsentKinds;
import '../application/nutrition_controller.dart';
import '../domain/nutrition.dart';
import 'meal_form_page.dart';

/// Nutrição (5.1): as refeições de um dia, os totais e o registro.
class NutritionPage extends ConsumerStatefulWidget {
  const NutritionPage({super.key});

  @override
  ConsumerState<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends ConsumerState<NutritionPage> {
  /// O dia escolhido; nulo = hoje no fuso do perfil (a API diz qual é).
  DateTime? _day;
  DateTime? _today;

  DateTime get _shown => _day ?? _today ?? dayOf(DateTime.now());

  void _shift(int days) {
    final target = dayOf(_shown.add(Duration(days: days)));
    setState(() => _day = target == _today ? null : target);
  }

  Future<void> _openMeal({Meal? meal}) async {
    await context.push(
      AppRoutes.nutritionMeal,
      extra: MealFormArgs(day: _shown, meal: meal),
    );
    ref.invalidate(dailyNutritionProvider(_day));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider).value;
    final consented =
        auth is Authenticated && auth.user.hasConsent(ConsentKinds.healthData);
    final daily = ref.watch(dailyNutritionProvider(_day));
    if (_day == null && daily.value != null) _today = dayOf(daily.value!.date);
    final localizations = MaterialLocalizations.of(context);
    final isToday = _day == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Nutrição')),
      floatingActionButton: consented
          ? FloatingActionButton.extended(
              onPressed: () => _openMeal(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Registrar refeição'),
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
            Row(
              children: [
                IconButton(
                  tooltip: 'Dia anterior',
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    isToday ? 'Hoje' : localizations.formatMediumDate(_shown),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Dia seguinte',
                  onPressed: isToday ? null : () => _shift(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: EvoSpace.md),
            if (!consented)
              const _ConsentCard()
            else
              ...daily.when(
                loading: () => const [EvoLoadingView(lines: 3)],
                error: (error, _) => [
                  EvoErrorView(
                    title: 'Não foi possível carregar o dia',
                    message: error is ApiException
                        ? error.message
                        : 'Erro inesperado.',
                    onRetry: () => ref.invalidate(dailyNutritionProvider(_day)),
                  ),
                ],
                data: (data) => [
                  _Totals(
                    totals: data.totals,
                    targets: data.targets,
                    onTargets: isToday
                        ? () => context.push(AppRoutes.nutritionTargets)
                        : null,
                  ),
                  const SizedBox(height: EvoSpace.xl),
                  if (data.meals.isEmpty)
                    EvoEmptyView(
                      icon: Icons.restaurant_outlined,
                      title: 'Nenhuma refeição neste dia',
                      message:
                          'Registre o que comeu para ver as calorias e os '
                          'macronutrientes do dia.',
                      actionLabel: 'Registrar refeição',
                      onAction: () => _openMeal(),
                    )
                  else
                    for (final meal in data.meals)
                      Padding(
                        padding: const EdgeInsets.only(bottom: EvoSpace.md),
                        child: _MealCard(
                          meal: meal,
                          onTap: () => _openMeal(meal: meal),
                        ),
                      ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.totals, this.targets, this.onTargets});

  final Nutrients totals;

  /// A meta que vale no dia (5.2); nula sem metas.
  final NutritionTargets? targets;

  /// Abre as metas; nulo nos dias passados.
  final VoidCallback? onTargets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goal = targets;
    final kcal = totals.kcal.round();
    Widget stat(String label, double value, int? target) => Expanded(
      child: Semantics(
        label: target == null
            ? '$label: ${formatGrams(value)} gramas'
            : '$label: ${formatGrams(value)} de $target gramas',
        excludeSemantics: true,
        child: Column(
          children: [
            Text('${formatGrams(value)} g', style: theme.textTheme.titleLarge),
            if (target != null) ...[
              Text('de $target g', style: theme.textTheme.labelSmall),
              const SizedBox(height: EvoSpace.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: EvoSpace.sm),
                child: LinearProgressIndicator(
                  value: progressOf(value, target),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(EvoRadius.pill),
                  backgroundColor: EvoColors.bgElevated,
                  color: EvoColors.accent,
                ),
              ),
              const SizedBox(height: EvoSpace.xs),
            ],
            Text(label, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
    final kcalTarget = goal?.kcal;
    return EvoCard(
      child: Column(
        children: [
          Semantics(
            label: kcalTarget == null
                ? 'Total do dia: $kcal quilocalorias'
                : 'Total do dia: $kcal de $kcalTarget quilocalorias',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${formatInt(kcal)} kcal',
                    style: theme.textTheme.displaySmall,
                  ),
                  if (kcalTarget != null)
                    TextSpan(
                      text: '  de ${formatInt(kcalTarget)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: EvoColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (kcalTarget != null) ...[
            const SizedBox(height: EvoSpace.sm),
            // O texto abaixo já diz quanto falta: a barra não é lida duas vezes.
            ExcludeSemantics(
              child: LinearProgressIndicator(
                value: progressOf(totals.kcal, kcalTarget),
                minHeight: 8,
                borderRadius: BorderRadius.circular(EvoRadius.pill),
                backgroundColor: EvoColors.bgElevated,
                color: EvoColors.accent,
              ),
            ),
            const SizedBox(height: EvoSpace.xs),
            Text(
              kcal <= kcalTarget
                  ? 'Faltam ${formatInt(kcalTarget - kcal)} kcal para a meta'
                  : '${formatInt(kcal - kcalTarget)} kcal acima da meta',
              style: theme.textTheme.labelSmall?.copyWith(
                color: EvoColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: EvoSpace.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              stat('Proteína', totals.proteinG, goal?.proteinG),
              stat('Carboidratos', totals.carbsG, goal?.carbsG),
              stat('Gordura', totals.fatG, goal?.fatG),
              if (totals.fiberG case final fiber?) stat('Fibras', fiber, null),
            ],
          ),
          // As metas valem a partir de hoje: num dia passado, só se vê a que valia.
          if (onTargets case final open?) ...[
            const SizedBox(height: EvoSpace.sm),
            TextButton.icon(
              onPressed: open,
              icon: const Icon(Icons.flag_outlined),
              label: Text(
                goal == null ? 'Definir metas do dia' : 'Editar metas',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.onTap});

  final Meal meal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(meal.localTime));
    return EvoCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${meal.label} · $time',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                '${meal.totals.kcal.round()} kcal',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: EvoSpace.xs),
          for (final item in meal.items)
            Text(
              '${item.foodName} · ${formatGrams(item.quantityG)} g · '
              '${item.nutrients.kcal.round()} kcal',
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: EvoSpace.xs),
          Text(
            describeMacros(meal.totals),
            style: theme.textTheme.labelSmall?.copyWith(
              color: EvoColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Alimentação é dado de saúde: sem o consentimento, nada é registrado.
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
            'O que você come é um dado de saúde (LGPD). Para registrar '
            'refeições, autorize o uso desses dados. Se desligar no perfil, as '
            'refeições registradas são apagadas.',
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
