import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../exercises/data/exercises_api.dart';
import '../../exercises/domain/exercise.dart';
import '../application/templates_controller.dart';
import '../domain/template.dart';

/// Fichas na ordem do usuário (Treino A, B, C...); segure e arraste para reordenar.
class TemplatesPage extends ConsumerWidget {
  const TemplatesPage({super.key});

  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    List<WorkoutTemplate> templates,
    int from,
    int to,
  ) async {
    final ordered = [...templates];
    final moved = ordered.removeAt(from);
    ordered.insert(to, moved);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(templatesProvider.notifier).reorder(ordered);
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Ordem não salva. ${error.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider);
    // Nomes dos músculos para o resumo de cada ficha.
    final muscles = {
      for (final m
          in ref.watch(exerciseOptionsProvider).value?.muscleGroups ??
              const <MuscleGroup>[])
        m.id: m.name,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Fichas de treino')),
      body: SafeArea(
        top: false,
        child: templates.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoLoadingView(lines: 5),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(EvoSpace.xl),
              child: EvoErrorView(
                title: 'Não foi possível carregar suas fichas',
                message: error is ApiException
                    ? error.message
                    : 'Erro inesperado.',
                onRetry: () => ref.invalidate(templatesProvider),
              ),
            ),
          ),
          data: (list) => list.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(EvoSpace.xl),
                    child: EvoEmptyView(
                      icon: Icons.list_alt_rounded,
                      title: 'Nenhuma ficha ainda',
                      message:
                          'Monte seus treinos com os exercícios da biblioteca: '
                          'séries, descanso e bi-sets.',
                      actionLabel: 'Criar ficha',
                      onAction: () => context.push(AppRoutes.templateNew),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.all(EvoSpace.xl),
                        itemCount: list.length,
                        // onReorderItem já entrega o índice final ajustado.
                        onReorderItem: (from, to) =>
                            _reorder(context, ref, list, from, to),
                        header: Padding(
                          padding: const EdgeInsets.only(bottom: EvoSpace.md),
                          child: Text(
                            'Segure e arraste para mudar a ordem.',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        itemBuilder: (context, index) => Padding(
                          key: ValueKey(list[index].id),
                          padding: const EdgeInsets.only(bottom: EvoSpace.md),
                          child: _TemplateCard(
                            template: list[index],
                            muscleNames: muscles,
                          ),
                        ),
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
                          label: 'Nova ficha',
                          icon: Icons.add_rounded,
                          onPressed: () => context.push(AppRoutes.templateNew),
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

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.muscleNames});

  final WorkoutTemplate template;
  final Map<String, String> muscleNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = switch (template.exerciseCount) {
      0 => 'Sem exercícios',
      1 => '1 exercício',
      final n => '$n exercícios',
    };
    final sets = template.setCount == 1
        ? '1 série'
        : '${template.setCount} séries';
    final muscles = [for (final id in template.muscles) ?muscleNames[id]]
        .join(', ');

    return EvoCard(
      onTap: () => context.push(AppRoutes.templateEdit(template.id)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  template.exerciseCount == 0 ? count : '$count · $sets',
                  style: theme.textTheme.bodyMedium,
                ),
                if (muscles.isNotEmpty) ...[
                  const SizedBox(height: EvoSpace.xs),
                  Text(muscles, style: theme.textTheme.labelSmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: EvoSpace.sm),
          const Icon(
            Icons.drag_indicator_rounded,
            color: EvoColors.textSecondary,
          ),
        ],
      ),
    );
  }
}
