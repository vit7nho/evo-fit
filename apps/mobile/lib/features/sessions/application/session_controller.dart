import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/sessions_api.dart';
import '../domain/session.dart';

/// Relógio de 1 segundo para o tempo de treino e o descanso. Nos testes é trocado por
/// um valor fixo: um relógio que avança sozinho impediria a tela de "assentar".
final clockTickProvider = StreamProvider<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
);

/// O treino aberto do usuário logado (nulo se não houver).
///
/// Depende do id da conta: ao trocar de conta, busca de novo. As gravações lançam
/// ApiException; a tela mostra a mensagem (na linha da série, quando é uma série).
class SessionController extends AsyncNotifier<WorkoutSession?> {
  SessionsApi get _api => ref.read(sessionsApiProvider);

  @override
  Future<WorkoutSession?> build() async {
    final userId = ref.watch(
      authControllerProvider.select(
        (auth) => switch (auth.value) {
          Authenticated(:final user) => user.id,
          _ => null,
        },
      ),
    );
    if (userId == null) return null;
    return ref.watch(sessionsApiProvider).current();
  }

  WorkoutSession get _session => state.value!;

  Future<WorkoutSession> start({String? templateId}) async {
    final session = await _api.start(templateId: templateId);
    state = AsyncData(session);
    return session;
  }

  /// Recarrega o treino aberto (ex.: o servidor disse que já existe um).
  Future<void> reload() async {
    state = AsyncData(await _api.current());
  }

  Future<void> pause() async =>
      state = AsyncData(await _api.pause(_session.id));

  Future<void> resume() async =>
      state = AsyncData(await _api.resume(_session.id));

  /// Finaliza e devolve o treino concluído (para o resumo); não há mais treino aberto.
  Future<WorkoutSession> finish({int? effort, String? notes}) async {
    final finished = await _api.finish(
      _session.id,
      effort: effort,
      notes: notes,
    );
    state = const AsyncData(null);
    return finished;
  }

  Future<void> discard() async {
    await _api.discard(_session.id);
    state = const AsyncData(null);
  }

  Future<void> addExercises(List<String> exerciseIds) async {
    var session = _session;
    for (final id in exerciseIds) {
      session = await _api.addExercise(session.id, id);
    }
    state = AsyncData(session);
  }

  Future<void> removeExercise(String entryId) async {
    await _api.removeExercise(_session.id, entryId);
    state = AsyncData(await _api.get(_session.id));
  }

  /// Registra uma série e a acrescenta ao exercício, sem recarregar o treino inteiro.
  Future<LoggedSet> logSet(String entryId, Map<String, Object?> body) async {
    final session = _session;
    final logged = await _api.addSet(session.id, entryId, body);
    _replaceSets(entryId, (sets) => [...sets, logged]);
    return logged;
  }

  Future<void> updateSet(
    String entryId,
    String setId,
    Map<String, Object?> changes,
  ) async {
    final updated = await _api.updateSet(_session.id, entryId, setId, changes);
    _replaceSets(
      entryId,
      (sets) => [for (final s in sets) s.id == setId ? updated : s],
    );
  }

  /// Apaga a série; os segmentos dela (drop, rest-pause) vão junto, como na API.
  Future<void> deleteSet(String entryId, String setId) async {
    await _api.deleteSet(_session.id, entryId, setId);
    _replaceSets(
      entryId,
      (sets) => [
        for (final s in sets)
          if (s.id != setId && s.parentSetId != setId) s,
      ],
    );
  }

  void _replaceSets(
    String entryId,
    List<LoggedSet> Function(List<LoggedSet>) change,
  ) {
    final session = state.value;
    if (session == null) return;
    final index = session.exercises.indexWhere((e) => e.id == entryId);
    if (index < 0) return;
    final entry = session.exercises[index];
    state = AsyncData(
      session.replaceExercise(index, entry.withSets(change(entry.sets))),
    );
  }
}

final sessionProvider =
    AsyncNotifierProvider<SessionController, WorkoutSession?>(
      SessionController.new,
    );

/// Descanso em contagem regressiva: guarda o horário de término, não um contador,
/// então segue certo mesmo se a tela for reconstruída ou o app ficar em segundo plano.
class RestTimer {
  const RestTimer({required this.endsAt, required this.totalS});

  final DateTime endsAt;
  final int totalS;

  int remainingAt(DateTime now) {
    final left = endsAt.difference(now).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }
}

class RestTimerController extends Notifier<RestTimer?> {
  @override
  RestTimer? build() => null;

  void start(int seconds) => state = RestTimer(
    endsAt: DateTime.now().add(Duration(seconds: seconds)),
    totalS: seconds,
  );

  /// +15 s ou −15 s; abaixo de zero encerra.
  void adjust(int seconds) {
    final current = state;
    if (current == null) return;
    final endsAt = current.endsAt.add(Duration(seconds: seconds));
    state = endsAt.isAfter(DateTime.now())
        ? RestTimer(endsAt: endsAt, totalS: current.totalS + seconds)
        : null;
  }

  void skip() => state = null;
}

final restTimerProvider = NotifierProvider<RestTimerController, RestTimer?>(
  RestTimerController.new,
);
