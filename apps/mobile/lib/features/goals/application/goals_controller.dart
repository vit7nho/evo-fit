import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/goals_api.dart';
import '../domain/goal.dart';

/// Metas do usuário logado, na ordem da API (ativas primeiro).
///
/// Depende do id da conta: ao sair ou trocar de conta a lista é descartada e
/// buscada de novo, então as metas de uma pessoa nunca aparecem para outra.
/// As gravações lançam ApiException; a tela exibe a mensagem.
class GoalsController extends AsyncNotifier<List<Goal>> {
  GoalsApi get _api => ref.read(goalsApiProvider);

  @override
  Future<List<Goal>> build() async {
    final userId = ref.watch(
      authControllerProvider.select(
        (auth) => switch (auth.value) {
          Authenticated(:final user) => user.id,
          _ => null,
        },
      ),
    );
    if (userId == null) return const [];
    return ref.watch(goalsApiProvider).list();
  }

  Future<Goal> create(Map<String, Object?> body) async {
    final goal = await _api.create(body);
    await _reload();
    return goal;
  }

  Future<Goal> updateGoal(String id, Map<String, Object?> changes) async {
    final goal = await _api.update(id, changes);
    await _reload();
    return goal;
  }

  Future<void> delete(String id) async {
    await _api.delete(id);
    await _reload();
  }

  /// A ordem depende de status, prioridade e prazo: a API é quem ordena.
  Future<void> _reload() async {
    state = AsyncData(await _api.list());
  }
}

final goalsProvider = AsyncNotifierProvider<GoalsController, List<Goal>>(
  GoalsController.new,
);
