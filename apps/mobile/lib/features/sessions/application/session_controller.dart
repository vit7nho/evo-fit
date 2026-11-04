import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/util/uuid.dart';
import '../../auth/application/auth_controller.dart';
import '../../history/application/history_controller.dart';
import '../data/session_draft.dart';
import '../data/sessions_api.dart';
import '../domain/session.dart';

/// Relógio de 1 segundo para o tempo de treino e o descanso. Nos testes é trocado por
/// um valor fixo: um relógio que avança sozinho impediria a tela de "assentar".
final clockTickProvider = StreamProvider<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()),
);

/// Estado do envio das séries guardadas no aparelho.
@immutable
class SessionSync {
  const SessionSync({
    this.pending = 0,
    this.offline = false,
    this.syncing = false,
    this.error,
  });

  /// Alterações de séries que ainda não chegaram ao servidor.
  final int pending;

  /// A última tentativa falhou por falta de conexão.
  final bool offline;
  final bool syncing;

  /// Uma série guardada que o servidor recusou (e foi descartada).
  final String? error;
}

class SessionSyncController extends Notifier<SessionSync> {
  @override
  SessionSync build() => const SessionSync();

  void set(SessionSync value) => state = value;
}

final sessionSyncProvider =
    NotifierProvider<SessionSyncController, SessionSync>(
      SessionSyncController.new,
    );

/// Falta de conexão (ou servidor fora do ar): a alteração fica na fila e é reenviada.
bool _isOffline(ApiException error) =>
    error.kind == ApiErrorKind.network || error.kind == ApiErrorKind.timeout;

/// Cópia profunda e mutável de um JSON.
Map<String, dynamic> _copy(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

/// O treino aberto do usuário logado (nulo se não houver), com rascunho local.
///
/// Cada série é enviada na hora; sem conexão, ela entra numa fila guardada no
/// aparelho (com um id gerado aqui, para o reenvio não duplicar) e aparece na tela
/// como pendente. A fila é reenviada em ordem quando a conexão volta, e o rascunho
/// (a última cópia do servidor + a fila) faz o treino reabrir mesmo sem rede
/// (ADR-037). Depende do id da conta: ao trocar de conta, busca de novo.
class SessionController extends AsyncNotifier<WorkoutSession?> {
  /// Intervalo entre as tentativas de reenvio enquanto houver fila.
  static const retryEvery = Duration(seconds: 20);

  SessionsApi get _api => ref.read(sessionsApiProvider);
  DraftStorage get _storage => ref.read(draftStorageProvider);

  String? _userId;

  /// O treino como o servidor conhece (com as séries já salvas lá).
  Map<String, dynamic>? _raw;
  DateTime _receivedAt = DateTime.now();

  /// Alterações de séries que ainda não chegaram ao servidor, na ordem.
  List<Map<String, dynamic>> _ops = [];
  bool _flushing = false;
  bool _offline = false;
  String? _syncError;
  Timer? _retry;

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
    ref.onDispose(() => _retry?.cancel());
    _userId = userId;
    _raw = null;
    _ops = [];
    _offline = false;
    _syncError = null;
    if (userId == null) {
      _publishSync();
      return null;
    }

    final draft = await _storage.read(userId);
    try {
      final current = await ref.watch(sessionsApiProvider).current();
      if (current == null) {
        // Nenhum treino aberto no servidor (finalizado ou descartado em outro
        // lugar): o rascunho não vale mais.
        await _storage.write(userId, null);
        _publishSync();
        return null;
      }
      _setRaw(current);
      if (draft != null && draft.session['id'] == current.id) {
        _ops = [...draft.ops];
      }
    } on ApiException catch (error) {
      // Sem conexão: reabre pelo rascunho, se houver.
      if (!_isOffline(error) || draft == null) rethrow;
      _raw = _copy(draft.session);
      _receivedAt = draft.receivedAt;
      _ops = [...draft.ops];
      _offline = true;
    }
    await _save();
    _publishSync();
    if (_ops.isNotEmpty) _scheduleRetry(Duration.zero);
    return _compose();
  }

  WorkoutSession get _session => state.value!;

  // --- ciclo de vida (precisa de conexão) ---

  Future<WorkoutSession> start({String? templateId}) async {
    final session = await _api.start(templateId: templateId);
    _setRaw(session);
    _ops = [];
    await _commit();
    return state.value!;
  }

  /// Recarrega o treino aberto (ex.: o servidor disse que já existe um).
  Future<void> reload() async {
    final current = await _api.current();
    if (current == null) {
      _raw = null;
      _ops = [];
    } else {
      _setRaw(current);
    }
    await _commit();
  }

  Future<void> pause() async {
    _setRaw(await _api.pause(_session.id));
    await _commit();
  }

  Future<void> resume() async {
    _setRaw(await _api.resume(_session.id));
    await _commit();
  }

  /// Finaliza e devolve o treino concluído (para o resumo); não há mais treino aberto.
  /// Antes, envia as séries guardadas no aparelho.
  Future<WorkoutSession> finish({int? effort, String? notes}) async {
    await _requireSynced('finalizar');
    final finished = await _api.finish(
      _session.id,
      effort: effort,
      notes: notes,
    );
    await _clear();
    // O treino novo entra no histórico e pode ter batido recordes.
    ref
      ..invalidate(sessionHistoryProvider)
      ..invalidate(recordsProvider);
    return finished;
  }

  Future<void> discard() async {
    await _api.discard(_session.id);
    await _clear();
  }

  Future<void> addExercises(List<String> exerciseIds) async {
    for (final id in exerciseIds) {
      _setRaw(await _api.addExercise(_session.id, id));
    }
    await _commit();
  }

  Future<void> updateExercise(
    String entryId,
    Map<String, Object?> changes,
  ) async {
    _setRaw(await _api.updateExercise(_session.id, entryId, changes));
    await _commit();
  }

  Future<void> removeExercise(String entryId) async {
    await _api.removeExercise(_session.id, entryId);
    _ops.removeWhere((op) => op['entry'] == entryId);
    _setRaw(await _api.get(_session.id));
    await _commit();
  }

  // --- séries (funcionam sem conexão) ---

  /// Registra uma série. [body] pode trazer `parent_set_id` com a identidade (no app)
  /// da série que um drop ou rest-pause continua. Sem conexão, a série fica guardada
  /// no aparelho e volta como pendente.
  /// [clientId]: quem chama pode gerar o id do app antes, para reconhecer a série
  /// quando ela aparecer no treino (antes de este método retornar).
  Future<LoggedSet> logSet(
    String entryId,
    Map<String, Object?> body, {
    String? clientId,
  }) async {
    clientId ??= uuidV4();
    final request = <String, dynamic>{...body, 'client_id': clientId};
    final parentKey = request.remove('parent_set_id') as String?;
    if (parentKey != null) {
      final parent = _set(entryId, parentKey);
      // O pai pelo id do app quando ele tem um: vale mesmo se ainda estiver na fila.
      if (parent?.clientId != null) {
        request['parent_client_id'] = parent!.clientId;
      } else {
        request['parent_set_id'] = parent?.serverId ?? parentKey;
      }
    }

    if (_ops.isEmpty) {
      try {
        final logged = await _api.addSet(_session.id, entryId, request);
        _rawAddSet(entryId, logged.raw!);
        await _commit();
        return _set(entryId, logged.id)!;
      } on ApiException catch (error) {
        if (!_isOffline(error)) rethrow;
        _offline = true;
      }
    }
    _ops.add({
      'op': 'create',
      'entry': entryId,
      'client_id': clientId,
      'body': request,
    });
    await _commit();
    _scheduleRetry(_offline ? retryEvery : Duration.zero);
    return _set(entryId, clientId)!;
  }

  Future<void> updateSet(
    String entryId,
    String setKey,
    Map<String, Object?> changes,
  ) async {
    final current = _set(entryId, setKey);
    if (current == null) return;
    if (current.pending) {
      // Ainda na fila: corrige o próprio envio pendente.
      final create = _ops.firstWhere((op) => op['client_id'] == setKey);
      (create['body'] as Map<String, dynamic>).addAll(changes);
      await _commit();
      return;
    }
    if (_ops.isEmpty) {
      try {
        final updated = await _api.updateSet(
          _session.id,
          entryId,
          current.serverId!,
          changes,
        );
        _rawReplaceSet(entryId, updated.raw!);
        await _commit();
        return;
      } on ApiException catch (error) {
        if (!_isOffline(error)) rethrow;
        _offline = true;
      }
    }
    _ops.add({
      'op': 'update',
      'entry': entryId,
      'set': current.serverId,
      'changes': Map<String, dynamic>.from(changes),
    });
    await _commit();
    _scheduleRetry(_offline ? retryEvery : Duration.zero);
  }

  /// Apaga a série; os segmentos dela (drop, rest-pause) vão junto, como na API.
  Future<void> deleteSet(String entryId, String setKey) async {
    final current = _set(entryId, setKey);
    if (current == null) return;
    if (current.pending) {
      // Nunca chegou ao servidor: some da fila (com os segmentos que dependiam dela).
      _ops.removeWhere(
        (op) =>
            op['client_id'] == setKey ||
            (op['body'] as Map<String, dynamic>?)?['parent_client_id'] ==
                setKey,
      );
      await _commit();
      return;
    }
    if (_ops.isEmpty) {
      try {
        await _api.deleteSet(_session.id, entryId, current.serverId!);
        _rawDeleteSet(entryId, current.serverId!);
        await _commit();
        return;
      } on ApiException catch (error) {
        if (!_isOffline(error)) rethrow;
        _offline = true;
      }
    }
    _ops.add({'op': 'delete', 'entry': entryId, 'set': current.serverId});
    await _commit();
    _scheduleRetry(_offline ? retryEvery : Duration.zero);
  }

  /// Envia a fila, em ordem. Para na primeira falta de conexão (tenta de novo
  /// depois); uma alteração que o servidor recusa é descartada e avisada.
  Future<void> flush() async {
    if (_flushing || _ops.isEmpty || _raw == null) return;
    _flushing = true;
    _retry?.cancel();
    _publishSync();
    final sessionId = _raw!['id'] as String;
    try {
      while (_ops.isNotEmpty) {
        final op = _ops.first;
        final entryId = op['entry'] as String;
        try {
          switch (op['op']) {
            case 'create':
              final logged = await _api.addSet(
                sessionId,
                entryId,
                Map<String, dynamic>.from(op['body'] as Map),
              );
              _rawAddSet(entryId, logged.raw!);
            case 'update':
              final updated = await _api.updateSet(
                sessionId,
                entryId,
                op['set'] as String,
                Map<String, dynamic>.from(op['changes'] as Map),
              );
              _rawReplaceSet(entryId, updated.raw!);
            case 'delete':
              try {
                await _api.deleteSet(sessionId, entryId, op['set'] as String);
              } on ApiException catch (error) {
                // Já não existe no servidor: o objetivo foi alcançado.
                if (error.statusCode != 404) rethrow;
              }
              _rawDeleteSet(entryId, op['set'] as String);
          }
          _ops.removeAt(0);
          _offline = false;
        } on ApiException catch (error) {
          if (_isOffline(error) || error.kind == ApiErrorKind.server) {
            _offline = _isOffline(error);
            _scheduleRetry(retryEvery);
            break;
          }
          // Recusada (ex.: o treino foi finalizado em outro aparelho): descarta,
          // com o que dependia dela.
          _syncError = error.message;
          final dropped = op['client_id'];
          _ops
            ..removeAt(0)
            ..removeWhere(
              (o) =>
                  dropped != null &&
                  (o['body'] as Map<String, dynamic>?)?['parent_client_id'] ==
                      dropped,
            );
        }
        await _commit();
      }
    } finally {
      _flushing = false;
      _publishSync();
    }
  }

  /// Esquece o aviso de série recusada (depois que a tela mostrou).
  void dismissSyncError() {
    _syncError = null;
    _publishSync();
  }

  // --- apoio ---

  Future<void> _requireSynced(String action) async {
    if (_ops.isEmpty) return;
    await flush();
    if (_ops.isNotEmpty) {
      throw ApiException(
        kind: ApiErrorKind.network,
        message:
            'Sem conexão: as séries guardadas no aparelho precisam ser enviadas antes '
            'de $action. Tente de novo quando a internet voltar.',
      );
    }
  }

  void _setRaw(WorkoutSession session) {
    _raw = _copy(session.raw!);
    _receivedAt = session.receivedAt;
  }

  LoggedSet? _set(String entryId, String key) {
    final session = state.value;
    if (session == null) return null;
    for (final entry in session.exercises) {
      if (entry.id != entryId) continue;
      for (final s in entry.sets) {
        if (s.id == key) return s;
      }
    }
    return null;
  }

  Map<String, dynamic>? _rawEntry(String entryId) {
    for (final e in (_raw?['exercises'] as List<dynamic>? ?? const [])) {
      if ((e as Map<String, dynamic>)['id'] == entryId) return e;
    }
    return null;
  }

  void _rawAddSet(String entryId, Map<String, dynamic> set) {
    final sets = _rawEntry(entryId)?['sets'] as List<dynamic>?;
    if (sets == null) return;
    // Reenvio idempotente devolve a mesma série: não duplica na cópia local.
    sets.removeWhere((s) => (s as Map)['id'] == set['id']);
    sets.add(_copy(set));
  }

  void _rawReplaceSet(String entryId, Map<String, dynamic> set) {
    final sets = _rawEntry(entryId)?['sets'] as List<dynamic>?;
    if (sets == null) return;
    final index = sets.indexWhere((s) => (s as Map)['id'] == set['id']);
    if (index >= 0) sets[index] = _copy(set);
  }

  void _rawDeleteSet(String entryId, String serverId) {
    (_rawEntry(entryId)?['sets'] as List<dynamic>?)?.removeWhere(
      (s) => (s as Map)['id'] == serverId || s['parent_set_id'] == serverId,
    );
  }

  /// O treino na tela: a cópia do servidor com a fila aplicada por cima.
  WorkoutSession? _compose() {
    final raw = _raw;
    if (raw == null) return null;
    var session = WorkoutSession.fromJson(_copy(raw), receivedAt: _receivedAt);
    for (final op in _ops) {
      final index = session.exercises.indexWhere((e) => e.id == op['entry']);
      if (index < 0) continue;
      final entry = session.exercises[index];
      List<LoggedSet> sets = entry.sets;
      switch (op['op']) {
        case 'create':
          final body = Map<String, dynamic>.from(op['body'] as Map);
          final parentServerId = body['parent_set_id'] as String?;
          final parentKey =
              body['parent_client_id'] as String? ??
              (parentServerId == null
                  ? null
                  : sets
                        .firstWhere(
                          (s) => s.serverId == parentServerId,
                          orElse: () => LoggedSet(
                            id: parentServerId,
                            position: 0,
                            kind: '',
                          ),
                        )
                        .id);
          final position =
              sets.fold(-1, (max, s) => s.position > max ? s.position : max) +
              1;
          sets = [
            ...sets,
            LoggedSet.pending(
              clientId: op['client_id'] as String,
              position: position,
              body: body,
              parentKey: parentKey,
            ),
          ];
        case 'update':
          final changes = Map<String, dynamic>.from(op['changes'] as Map);
          sets = [
            for (final s in sets)
              s.serverId == op['set'] ? s.withChanges(changes) : s,
          ];
        case 'delete':
          final target = sets.where((s) => s.serverId == op['set']).firstOrNull;
          if (target != null) {
            sets = [
              for (final s in sets)
                if (s.id != target.id && s.parentSetId != target.id) s,
            ];
          }
      }
      session = session.replaceExercise(index, entry.withSets(sets));
    }
    return session;
  }

  Future<void> _commit() async {
    state = AsyncData(_compose());
    await _save();
    _publishSync();
  }

  Future<void> _save() async {
    final userId = _userId;
    if (userId == null) return;
    final raw = _raw;
    await _storage.write(
      userId,
      raw == null
          ? null
          : SessionDraft(session: raw, receivedAt: _receivedAt, ops: _ops),
    );
  }

  Future<void> _clear() async {
    _raw = null;
    _ops = [];
    _retry?.cancel();
    _offline = false;
    await _commit();
  }

  void _scheduleRetry(Duration delay) {
    _retry?.cancel();
    if (_ops.isEmpty) return;
    _retry = Timer(delay, () => unawaited(flush()));
  }

  void _publishSync() {
    ref
        .read(sessionSyncProvider.notifier)
        .set(
          SessionSync(
            pending: _ops.length,
            offline: _offline && _ops.isNotEmpty,
            syncing: _flushing,
            error: _syncError,
          ),
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
