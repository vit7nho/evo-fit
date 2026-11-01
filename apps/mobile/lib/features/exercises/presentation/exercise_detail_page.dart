import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../profile/domain/profile.dart';
import '../application/exercises_controller.dart';
import '../data/exercises_api.dart';
import '../domain/exercise.dart';

/// Detalhe de um exercício: músculos, características e como fazer.
class ExerciseDetailPage extends ConsumerStatefulWidget {
  const ExerciseDetailPage({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  ConsumerState<ExerciseDetailPage> createState() => _ExerciseDetailPageState();
}

class _ExerciseDetailPageState extends ConsumerState<ExerciseDetailPage> {
  bool _saving = false;

  Future<void> _setActive(Exercise exercise, {required bool active}) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(exercisesProvider.notifier).updateExercise(exercise.id, {
        'is_active': active,
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            active ? 'Exercício restaurado' : 'Exercício arquivado',
          ),
        ),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercises = ref.watch(exercisesProvider);
    final options = ref.watch(exerciseOptionsProvider).value;

    Widget message(String title, String text, {VoidCallback? retry}) =>
        Scaffold(
          appBar: AppBar(),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(EvoSpace.xl),
              child: EvoErrorView(title: title, message: text, onRetry: retry),
            ),
          ),
        );

    return exercises.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.all(EvoSpace.xl),
          child: EvoLoadingView(lines: 6),
        ),
      ),
      error: (error, _) => message(
        'Não foi possível carregar o exercício',
        error is ApiException ? error.message : 'Erro inesperado.',
        retry: () => ref.invalidate(exercisesProvider),
      ),
      data: (all) {
        final exercise = all
            .where((e) => e.id == widget.exerciseId)
            .firstOrNull;
        if (exercise == null) {
          return message(
            'Exercício não encontrado',
            'Volte para a biblioteca e escolha outro.',
          );
        }
        return _detail(context, exercise, options);
      },
    );
  }

  Widget _detail(
    BuildContext context,
    Exercise exercise,
    ExerciseOptions? options,
  ) {
    final theme = Theme.of(context);
    String label(List<Option> Function(ExerciseOptions) list, String code) =>
        options == null ? '' : ProfileOptions.labelOf(list(options), code);
    final traits = [
      label((o) => o.equipment, exercise.equipment),
      label((o) => o.mechanics, exercise.mechanics),
      label((o) => o.loadTypes, exercise.loadType),
      if (exercise.unilateral) 'Um lado por vez',
    ].where((t) => t.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(exercise.isCustom ? 'Seu exercício' : 'Exercício'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(EvoSpace.xl),
          children: [
            Semantics(
              header: true,
              child: Text(exercise.name, style: theme.textTheme.displaySmall),
            ),
            if (!exercise.isActive) ...[
              const SizedBox(height: EvoSpace.sm),
              Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: EvoColors.textSecondary,
                  ),
                  const SizedBox(width: EvoSpace.xs),
                  Text('Arquivado', style: theme.textTheme.bodyMedium),
                ],
              ),
            ],
            const SizedBox(height: EvoSpace.lg),
            Wrap(
              spacing: EvoSpace.sm,
              runSpacing: EvoSpace.sm,
              children: [for (final trait in traits) _Tag(trait)],
            ),
            if (exercise.images.length >= 2) ...[
              const SizedBox(height: EvoSpace.x2xl),
              _Photos(exercise: exercise),
            ],
            const SizedBox(height: EvoSpace.x2xl),
            _MuscleSection(
              title: 'Músculos principais',
              muscles: exercise.primaryMuscles,
              strong: true,
            ),
            if (exercise.secondaryMuscles.isNotEmpty) ...[
              const SizedBox(height: EvoSpace.xl),
              _MuscleSection(
                title: 'Também trabalha',
                muscles: exercise.secondaryMuscles,
                strong: false,
              ),
            ],
            if ((exercise.instructions ?? '').isNotEmpty) ...[
              const SizedBox(height: EvoSpace.x2xl),
              Semantics(
                header: true,
                child: Text('Como fazer', style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: EvoSpace.sm),
              Text(exercise.instructions!, style: theme.textTheme.bodyLarge),
            ],
            if (!exercise.isCustom) ...[
              const SizedBox(height: EvoSpace.x2xl),
              Text(
                'Orientação geral do catálogo do EvoFit. Ajuste a execução e a carga '
                'com um profissional de Educação Física.',
                style: theme.textTheme.labelSmall,
              ),
            ],
            if (exercise.isCustom) ...[
              const SizedBox(height: EvoSpace.x2xl),
              EvoButton(
                label: 'Editar',
                icon: Icons.edit_outlined,
                variant: EvoButtonVariant.secondary,
                onPressed: _saving
                    ? null
                    : () => context.push(AppRoutes.exerciseEdit(exercise.id)),
              ),
              const SizedBox(height: EvoSpace.sm),
              TextButton(
                onPressed: _saving
                    ? null
                    : () => _setActive(exercise, active: !exercise.isActive),
                child: Text(
                  exercise.isActive
                      ? 'Arquivar exercício'
                      : 'Restaurar exercício',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MuscleSection extends StatelessWidget {
  const _MuscleSection({
    required this.title,
    required this.muscles,
    required this.strong,
  });

  final String title;
  final List<ExerciseMuscle> muscles;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: EvoSpace.sm),
        Wrap(
          spacing: EvoSpace.sm,
          runSpacing: EvoSpace.sm,
          children: [
            for (final muscle in muscles) _Tag(muscle.name, strong: strong),
          ],
        ),
      ],
    );
  }
}

/// Etiqueta só de leitura (não é botão): preta para os principais, clara para o resto.
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: EvoSpace.md,
        vertical: EvoSpace.xs + 2,
      ),
      decoration: BoxDecoration(
        color: strong ? EvoColors.accent : EvoColors.bgSurface,
        borderRadius: BorderRadius.circular(EvoRadius.pill),
        border: Border.all(
          color: strong ? EvoColors.accent : EvoColors.borderSubtle,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: strong ? EvoColors.onAccent : EvoColors.textPrimary,
          fontSize: EvoFontSize.bodySm,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Posição inicial e final, uma abaixo da outra, com o crédito da base de fotos.
class _Photos extends ConsumerWidget {
  const _Photos({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(appConfigProvider).apiBaseUrl;
    final theme = Theme.of(context);
    Widget photo(String path, String caption) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // O rótulo fica fora da Image: vale também quando a foto não carrega.
        Semantics(
          image: true,
          label: '${exercise.name}: $caption',
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(EvoRadius.input),
            child: AspectRatio(
              // Quase todas as fotos da base são 3:2 e ocupam a largura toda;
              // "contain" mostra inteiras as poucas em pé, sem cortar cabeça ou pés.
              aspectRatio: 3 / 2,
              child: ColoredBox(
                color: EvoColors.bgElevated,
                child: Image.network(
                  '$base$path',
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const ColoredBox(color: EvoColors.bgElevated),
                  // Sem rede, o espaço continua com um aviso em vez de quebrar a tela.
                  errorBuilder: (context, error, stack) => Container(
                    color: EvoColors.bgElevated,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(EvoSpace.sm),
                    child: Text(
                      'Foto indisponível',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: EvoSpace.xs),
        // A legenda já está no rótulo da foto: o TalkBack não lê duas vezes.
        ExcludeSemantics(
          child: Text(caption, style: theme.textTheme.labelSmall),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        photo(exercise.images[0], 'Início'),
        const SizedBox(height: EvoSpace.md),
        photo(exercise.images[1], 'Fim'),
        const SizedBox(height: EvoSpace.sm),
        Text(
          'Fotos: free-exercise-db (domínio público). A variação pode diferir um '
          'pouco da descrição abaixo.',
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}
