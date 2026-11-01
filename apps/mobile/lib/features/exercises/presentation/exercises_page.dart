import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_selection.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../profile/domain/profile.dart';
import '../application/exercises_controller.dart';
import '../data/exercises_api.dart';
import '../domain/exercise.dart';

/// Biblioteca: busca sem acentos, filtro por músculo, "meus" e "só o que tenho".
class ExercisesPage extends ConsumerStatefulWidget {
  const ExercisesPage({super.key});

  @override
  ConsumerState<ExercisesPage> createState() => _ExercisesPageState();
}

class _ExercisesPageState extends ConsumerState<ExercisesPage> {
  final _search = TextEditingController();
  String? _muscle;
  bool _mineOnly = false;
  bool _onlyAvailable = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearFilters() => setState(() {
    _search.clear();
    _muscle = null;
    _mineOnly = false;
    _onlyAvailable = false;
  });

  @override
  Widget build(BuildContext context) {
    final exercises = ref.watch(exercisesProvider);
    final options = ref.watch(exerciseOptionsProvider).value;
    final auth = ref.watch(authControllerProvider).value;
    final available = auth is Authenticated
        ? availableEquipment(auth.user.profile.equipment)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Exercícios')),
      body: SafeArea(
        top: false,
        child: exercises.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoLoadingView(lines: 6),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(EvoSpace.xl),
              child: EvoErrorView(
                title: 'Não foi possível carregar os exercícios',
                message: error is ApiException
                    ? error.message
                    : 'Erro inesperado.',
                onRetry: () => ref.invalidate(exercisesProvider),
              ),
            ),
          ),
          data: (all) {
            final filtered = filterExercises(
              all,
              query: _search.text,
              muscle: _muscle,
              equipment: _onlyAvailable ? available : null,
              mineOnly: _mineOnly,
            );
            final active = filtered.where((e) => e.isActive).toList();
            // Arquivados só aparecem em "Meus", para poder restaurá-los.
            final archived = _mineOnly
                ? filtered.where((e) => !e.isActive).toList()
                : const <Exercise>[];
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    EvoSpace.xl,
                    EvoSpace.sm,
                    EvoSpace.xl,
                    EvoSpace.md,
                  ),
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Buscar exercício',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpar busca',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _search.clear,
                            ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: EvoSpace.xl),
                  child: Row(
                    children: [
                      EvoChip(
                        label: 'Meus',
                        selected: _mineOnly,
                        onTap: () => setState(() => _mineOnly = !_mineOnly),
                      ),
                      if (available != null) ...[
                        const SizedBox(width: EvoSpace.sm),
                        EvoChip(
                          label: 'Só o que tenho',
                          selected: _onlyAvailable,
                          onTap: () =>
                              setState(() => _onlyAvailable = !_onlyAvailable),
                        ),
                      ],
                      for (final muscle
                          in options?.muscleGroups ??
                              const <MuscleGroup>[]) ...[
                        const SizedBox(width: EvoSpace.sm),
                        EvoChip(
                          label: muscle.name,
                          selected: _muscle == muscle.id,
                          onTap: () => setState(
                            () => _muscle = _muscle == muscle.id
                                ? null
                                : muscle.id,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: EvoSpace.sm),
                Expanded(
                  child: active.isEmpty && archived.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(EvoSpace.xl),
                            child: EvoEmptyView(
                              icon: Icons.search_off_rounded,
                              title: 'Nenhum exercício encontrado',
                              message:
                                  _mineOnly && all.every((e) => !e.isCustom)
                                  ? 'Você ainda não criou exercícios.'
                                  : 'Tente outra busca ou limpe os filtros.',
                              actionLabel: 'Limpar filtros',
                              onAction: _clearFilters,
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(
                            EvoSpace.xl,
                            EvoSpace.sm,
                            EvoSpace.xl,
                            EvoSpace.xl,
                          ),
                          children: [
                            Semantics(
                              liveRegion: true,
                              child: Text(switch (active.length) {
                                0 => 'Nenhum exercício ativo',
                                1 => '1 exercício',
                                final n => '$n exercícios',
                              }, style: Theme.of(context).textTheme.labelSmall),
                            ),
                            const SizedBox(height: EvoSpace.sm),
                            for (final exercise in active)
                              _ExerciseTile(
                                exercise: exercise,
                                options: options,
                              ),
                            if (archived.isNotEmpty) ...[
                              const SizedBox(height: EvoSpace.xl),
                              Semantics(
                                header: true,
                                child: Text(
                                  'Arquivados',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              const SizedBox(height: EvoSpace.sm),
                              for (final exercise in archived)
                                _ExerciseTile(
                                  exercise: exercise,
                                  options: options,
                                ),
                            ],
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    EvoSpace.xl,
                    EvoSpace.sm,
                    EvoSpace.xl,
                    EvoSpace.lg,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: EvoButton(
                      label: 'Criar exercício',
                      icon: Icons.add_rounded,
                      variant: EvoButtonVariant.secondary,
                      onPressed: () => context.push(AppRoutes.exerciseNew),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.exercise, required this.options});

  final Exercise exercise;
  final ExerciseOptions? options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      exercise.primaryMuscles.map((m) => m.name).join(', '),
      if (options != null)
        ProfileOptions.labelOf(options!.equipment, exercise.equipment),
    ].where((s) => s.isNotEmpty).join(' · ');

    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => context.push(AppRoutes.exerciseDetail(exercise.id)),
        borderRadius: BorderRadius.circular(EvoRadius.input),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: EvoSpace.md),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: EvoColors.borderSubtle)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise.name, style: theme.textTheme.titleMedium),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(details, style: theme.textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
              if (exercise.isCustom) ...[
                const SizedBox(width: EvoSpace.sm),
                const _Badge('Seu'),
              ],
              const SizedBox(width: EvoSpace.sm),
              const Icon(
                Icons.chevron_right_rounded,
                color: EvoColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EvoSpace.sm, vertical: 2),
      decoration: BoxDecoration(
        color: EvoColors.bgElevated,
        borderRadius: BorderRadius.circular(EvoRadius.pill),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
