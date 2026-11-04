import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/plans_api.dart';
import '../domain/plan.dart';

/// Id da conta logada: ao sair ou trocar de conta, os planos são descartados e os de
/// uma pessoa nunca aparecem para outra.
String? _userId(Ref ref) => ref.watch(
  authControllerProvider.select(
    (auth) => switch (auth.value) {
      Authenticated(:final user) => user.id,
      _ => null,
    },
  ),
);

/// Planos oferecidos. Dependem do perfil (limitações, histórico): buscados de novo a
/// cada visita.
final planTemplatesProvider = FutureProvider.autoDispose<List<PlanTemplate>>((
  ref,
) {
  _userId(ref);
  return ref.watch(plansApiProvider).templates();
});

/// Planos da pessoa (resumo), do mais recente. As gravações lançam ApiException.
class PlansController extends AsyncNotifier<List<TrainingPlan>> {
  PlansApi get _api => ref.read(plansApiProvider);

  @override
  Future<List<TrainingPlan>> build() async {
    if (_userId(ref) == null) return const [];
    return ref.watch(plansApiProvider).list();
  }

  Future<TrainingPlan> start({
    required String kind,
    required List<int> weekdays,
    required DateTime startDate,
  }) async {
    final plan = await _api.create(
      kind: kind,
      weekdays: weekdays,
      startDate: startDate,
    );
    state = AsyncData(await _api.list());
    return plan;
  }
}

final plansProvider =
    AsyncNotifierProvider<PlansController, List<TrainingPlan>>(
      PlansController.new,
    );

/// O plano em andamento (nulo se não houver).
final activePlanProvider = Provider<AsyncValue<TrainingPlan?>>(
  (ref) => ref
      .watch(plansProvider)
      .whenData((plans) => plans.where((p) => p.active).firstOrNull),
);

/// Um plano com as sessões; marcar, desmarcar e encerrar atualizam também a lista.
class PlanController extends AsyncNotifier<TrainingPlan> {
  PlanController(this.planId);

  final String planId;
  PlansApi get _api => ref.read(plansApiProvider);

  @override
  Future<TrainingPlan> build() async {
    _userId(ref);
    return ref.watch(plansApiProvider).get(planId);
  }

  Future<TrainingPlan> link(String sessionId, String activityId) =>
      _apply(_api.link(planId, sessionId, activityId));

  Future<TrainingPlan> unlink(String sessionId) =>
      _apply(_api.unlink(planId, sessionId));

  Future<TrainingPlan> end() => _apply(_api.end(planId));

  Future<TrainingPlan> _apply(Future<TrainingPlan> call) async {
    final plan = await call;
    state = AsyncData(plan);
    ref.invalidate(plansProvider);
    return plan;
  }
}

final planProvider =
    AsyncNotifierProvider.family<PlanController, TrainingPlan, String>(
      PlanController.new,
    );
