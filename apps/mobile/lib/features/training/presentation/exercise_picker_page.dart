import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_selection.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../exercises/application/exercises_controller.dart';
import '../../exercises/data/exercises_api.dart';
import '../../exercises/domain/exercise.dart';
import '../domain/template.dart';

/// Escolhe exercícios da biblioteca (vários de uma vez) para a ficha.
///
/// Devolve os escolhidos na ordem em que foram marcados.
class ExercisePickerPage extends ConsumerStatefulWidget {
  const ExercisePickerPage({super.key});

  @override
  ConsumerState<ExercisePickerPage> createState() => _ExercisePickerPageState();
}

class _ExercisePickerPageState extends ConsumerState<ExercisePickerPage> {
  final _search = TextEditingController();
  final _selected = <Exercise>[];
  String? _muscle;

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

  void _toggle(Exercise exercise) => setState(() {
    if (!_selected.remove(exercise)) _selected.add(exercise);
  });

  void _done() {
    Navigator.of(context).pop([
      for (final e in _selected)
        TemplateExercise(
          id: e.id,
          name: e.name,
          equipment: e.equipment,
          loadType: e.loadType,
          isActive: e.isActive,
          primaryMuscles: [for (final m in e.primaryMuscles) m.id],
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final exercises = ref.watch(exercisesProvider);
    final options = ref.watch(exerciseOptionsProvider).value;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar exercícios')),
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
            final visible = filterExercises(
              all.where((e) => e.isActive).toList(),
              query: _search.text,
              muscle: _muscle,
            );
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
                    decoration: const InputDecoration(
                      labelText: 'Buscar exercício',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: EvoSpace.xl),
                  child: Row(
                    children: [
                      for (final (i, m)
                          in (options?.muscleGroups ?? const <MuscleGroup>[])
                              .indexed) ...[
                        if (i > 0) const SizedBox(width: EvoSpace.sm),
                        EvoChip(
                          label: m.name,
                          selected: _muscle == m.id,
                          onTap: () => setState(
                            () => _muscle = _muscle == m.id ? null : m.id,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: EvoSpace.sm),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: EvoSpace.xl,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final exercise = visible[index];
                      final order = _selected.indexOf(exercise);
                      return Material(
                        type: MaterialType.transparency,
                        child: CheckboxListTile(
                          value: order >= 0,
                          onChanged: (_) => _toggle(exercise),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            exercise.name,
                            style: theme.textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            exercise.primaryMuscles
                                .map((m) => m.name)
                                .join(', '),
                            style: theme.textTheme.bodyMedium,
                          ),
                          // A ordem de marcação é a ordem em que entram na ficha.
                          secondary: order >= 0
                              ? Text(
                                  '${order + 1}º',
                                  style: theme.textTheme.titleMedium,
                                )
                              : null,
                        ),
                      );
                    },
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
                      label: _selected.isEmpty
                          ? 'Adicionar'
                          : 'Adicionar (${_selected.length})',
                      // Sempre ativo (ADR-027): sem escolha, diz o que falta.
                      onPressed: _selected.isEmpty
                          ? () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Marque pelo menos um exercício.',
                                ),
                              ),
                            )
                          : _done,
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
