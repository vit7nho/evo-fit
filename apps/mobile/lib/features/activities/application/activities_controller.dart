import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../history/domain/history.dart' show Paged;
import '../data/activities_api.dart';
import '../domain/activity.dart';

/// Atividades da conta logada, da mais recente, paginadas ("Carregar mais").
///
/// Depende do id da conta: ao sair ou trocar de conta a lista é descartada, então
/// as atividades de uma pessoa nunca aparecem para outra. As gravações lançam
/// ApiException; a tela exibe a mensagem.
class ActivitiesController extends AsyncNotifier<Paged<Activity>> {
  ActivitiesApi get _api => ref.read(activitiesApiProvider);
  bool _loadingMore = false;

  @override
  Future<Paged<Activity>> build() async {
    final userId = ref.watch(
      authControllerProvider.select(
        (auth) => switch (auth.value) {
          Authenticated(:final user) => user.id,
          _ => null,
        },
      ),
    );
    if (userId == null) return const Paged([], null);
    return ref.watch(activitiesApiProvider).list();
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current?.nextBefore == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final next = await _api.list(before: current!.nextBefore);
      state = AsyncData(
        Paged([...current.items, ...next.items], next.nextBefore),
      );
    } finally {
      _loadingMore = false;
    }
  }

  Future<Activity> create(Map<String, Object?> body) async {
    final activity = await _api.create(body);
    await _reload();
    return activity;
  }

  Future<Activity> updateActivity(
    String id,
    Map<String, Object?> changes,
  ) async {
    final activity = await _api.update(id, changes);
    await _reload();
    return activity;
  }

  Future<void> delete(String id) async {
    await _api.delete(id);
    await _reload();
  }

  /// A data pode ter mudado (e com ela a ordem): a API é quem ordena.
  Future<void> _reload() async {
    state = AsyncData(await _api.list());
  }
}

final activitiesProvider =
    AsyncNotifierProvider<ActivitiesController, Paged<Activity>>(
      ActivitiesController.new,
    );

/// Uma atividade, para a edição (vinda da lista quando já carregada).
final activityProvider = FutureProvider.family<Activity, String>((ref, id) {
  final loaded = ref
      .read(activitiesProvider)
      .value
      ?.items
      .where((a) => a.id == id)
      .firstOrNull;
  return loaded ?? ref.watch(activitiesApiProvider).get(id);
});
