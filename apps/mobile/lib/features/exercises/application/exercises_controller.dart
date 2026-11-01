import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/exercises_api.dart';
import '../domain/exercise.dart';

/// Biblioteca do usuário logado (catálogo + exercícios próprios), em ordem alfabética.
///
/// Depende do id da conta: ao trocar de conta a lista é buscada de novo, então os
/// exercícios próprios de uma pessoa nunca aparecem para outra. A busca e os filtros
/// rodam no aparelho (filterExercises): a biblioteca inteira cabe em memória.
class ExercisesController extends AsyncNotifier<List<Exercise>> {
  ExercisesApi get _api => ref.read(exercisesApiProvider);

  @override
  Future<List<Exercise>> build() async {
    final userId = ref.watch(
      authControllerProvider.select(
        (auth) => switch (auth.value) {
          Authenticated(:final user) => user.id,
          _ => null,
        },
      ),
    );
    if (userId == null) return const [];
    return ref.watch(exercisesApiProvider).list();
  }

  Future<Exercise> create(Map<String, Object?> body) async {
    final exercise = await _api.create(body);
    await _reload();
    return exercise;
  }

  Future<Exercise> updateExercise(
    String id,
    Map<String, Object?> changes,
  ) async {
    final exercise = await _api.update(id, changes);
    await _reload();
    return exercise;
  }

  /// A ordem alfabética (sem acentos) é a da API.
  Future<void> _reload() async {
    state = AsyncData(await _api.list());
  }
}

final exercisesProvider =
    AsyncNotifierProvider<ExercisesController, List<Exercise>>(
      ExercisesController.new,
    );
