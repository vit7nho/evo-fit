import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../sessions/data/sessions_api.dart';
import '../../sessions/domain/session.dart';
import '../data/history_api.dart';
import '../domain/history.dart';

/// Id da conta logada: os provedores abaixo dependem dele, então o histórico de
/// uma pessoa nunca aparece para outra depois de trocar de conta.
String? _userId(Ref ref) => ref.watch(
  authControllerProvider.select(
    (auth) => switch (auth.value) {
      Authenticated(:final user) => user.id,
      _ => null,
    },
  ),
);

/// Treinos concluídos, paginados ("Carregar mais").
class SessionHistoryController extends AsyncNotifier<Paged<SessionSummary>> {
  bool _loadingMore = false;

  @override
  Future<Paged<SessionSummary>> build() async {
    if (_userId(ref) == null) return const Paged([], null);
    return ref.watch(historyApiProvider).sessions();
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current?.nextBefore == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final next = await ref
          .read(historyApiProvider)
          .sessions(before: current!.nextBefore);
      state = AsyncData(
        Paged([...current.items, ...next.items], next.nextBefore),
      );
    } finally {
      _loadingMore = false;
    }
  }
}

final sessionHistoryProvider =
    AsyncNotifierProvider<SessionHistoryController, Paged<SessionSummary>>(
      SessionHistoryController.new,
    );

/// Recordes por exercício, do feito mais recentemente.
final recordsProvider = FutureProvider<List<ExerciseRecords>>((ref) async {
  if (_userId(ref) == null) return const [];
  return ref.watch(historyApiProvider).records();
});

/// Um treino (para o detalhe no histórico).
final workoutDetailProvider = FutureProvider.family<WorkoutSession, String>((
  ref,
  sessionId,
) async {
  _userId(ref);
  return ref.watch(sessionsApiProvider).get(sessionId);
});

/// Histórico de um exercício, paginado.
class ExerciseHistoryController extends AsyncNotifier<ExerciseHistory> {
  ExerciseHistoryController(this.exerciseId);

  final String exerciseId;
  bool _loadingMore = false;

  @override
  Future<ExerciseHistory> build() async {
    _userId(ref);
    return ref.watch(historyApiProvider).exercise(exerciseId);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current?.nextBefore == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final next = await ref
          .read(historyApiProvider)
          .exercise(exerciseId, before: current!.nextBefore);
      state = AsyncData(current.append(next));
    } finally {
      _loadingMore = false;
    }
  }
}

final exerciseHistoryProvider =
    AsyncNotifierProvider.family<
      ExerciseHistoryController,
      ExerciseHistory,
      String
    >(ExerciseHistoryController.new);
