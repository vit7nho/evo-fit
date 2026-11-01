import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/templates_api.dart';
import '../domain/template.dart';

/// Fichas do usuário logado, na ordem dele.
///
/// Depende do id da conta: ao trocar de conta a lista é buscada de novo, então as
/// fichas de uma pessoa nunca aparecem para outra. As gravações lançam ApiException.
class TemplatesController extends AsyncNotifier<List<WorkoutTemplate>> {
  TemplatesApi get _api => ref.read(templatesApiProvider);

  @override
  Future<List<WorkoutTemplate>> build() async {
    final userId = ref.watch(
      authControllerProvider.select(
        (auth) => switch (auth.value) {
          Authenticated(:final user) => user.id,
          _ => null,
        },
      ),
    );
    if (userId == null) return const [];
    return ref.watch(templatesApiProvider).list();
  }

  Future<WorkoutTemplate> create(Map<String, Object?> body) async {
    final template = await _api.create(body);
    await _reload();
    return template;
  }

  Future<WorkoutTemplate> replace(String id, Map<String, Object?> body) async {
    final template = await _api.replace(id, body);
    await _reload();
    return template;
  }

  Future<void> delete(String id) async {
    await _api.delete(id);
    await _reload();
  }

  /// Mostra a nova ordem na hora; se a API recusar, volta à ordem anterior.
  Future<void> reorder(List<WorkoutTemplate> ordered) async {
    final previous = state;
    state = AsyncData(ordered);
    try {
      state = AsyncData(await _api.reorder([for (final t in ordered) t.id]));
    } catch (_) {
      state = previous;
      rethrow;
    }
  }

  Future<void> _reload() async {
    state = AsyncData(await _api.list());
  }
}

final templatesProvider =
    AsyncNotifierProvider<TemplatesController, List<WorkoutTemplate>>(
      TemplatesController.new,
    );
