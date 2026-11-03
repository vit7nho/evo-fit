import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/session.dart';

/// Treinos em andamento (docs/API.md). Cada série é salva na hora em que é feita.
class SessionsApi {
  const SessionsApi(this._dio);

  final Dio _dio;

  static const _base = '/workout-sessions';

  WorkoutSession _session(Response<Map<String, dynamic>> response) =>
      WorkoutSession.fromJson(response.data!);

  /// O treino aberto, ou nulo (a API responde 204 quando não há).
  Future<WorkoutSession?> current() => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>('$_base/current');
    return response.statusCode == 204 || response.data == null
        ? null
        : _session(response);
  });

  Future<WorkoutSession> get(String id) => guardApiCall(
    () async => _session(await _dio.get<Map<String, dynamic>>('$_base/$id')),
  );

  Future<WorkoutSession> start({String? templateId}) => guardApiCall(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      _base,
      data: {'template_id': ?templateId},
    );
    return _session(response);
  });

  Future<WorkoutSession> pause(String id) => _action(id, 'pause');

  Future<WorkoutSession> resume(String id) => _action(id, 'resume');

  Future<WorkoutSession> finish(String id, {int? effort, String? notes}) =>
      guardApiCall(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '$_base/$id/finish',
          data: {'perceived_effort': effort, 'notes': notes},
        );
        return _session(response);
      });

  Future<void> discard(String id) =>
      guardApiCall(() => _dio.post<void>('$_base/$id/discard'));

  Future<WorkoutSession> addExercise(String id, String exerciseId) =>
      guardApiCall(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '$_base/$id/exercises',
          data: {'exercise_id': exerciseId},
        );
        return _session(response);
      });

  /// Descanso e nota do exercício neste treino (a ficha não muda).
  Future<WorkoutSession> updateExercise(
    String id,
    String entryId,
    Map<String, Object?> changes,
  ) => guardApiCall(() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '$_base/$id/exercises/$entryId',
      data: changes,
    );
    return _session(response);
  });

  Future<void> removeExercise(String id, String entryId) =>
      guardApiCall(() => _dio.delete<void>('$_base/$id/exercises/$entryId'));

  Future<LoggedSet> addSet(
    String id,
    String entryId,
    Map<String, Object?> body,
  ) => guardApiCall(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_base/$id/exercises/$entryId/sets',
      data: body,
    );
    return LoggedSet.fromJson(response.data!);
  });

  Future<LoggedSet> updateSet(
    String id,
    String entryId,
    String setId,
    Map<String, Object?> changes,
  ) => guardApiCall(() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '$_base/$id/exercises/$entryId/sets/$setId',
      data: changes,
    );
    return LoggedSet.fromJson(response.data!);
  });

  Future<void> deleteSet(String id, String entryId, String setId) =>
      guardApiCall(
        () => _dio.delete<void>('$_base/$id/exercises/$entryId/sets/$setId'),
      );

  Future<WorkoutSession> _action(String id, String action) =>
      guardApiCall(() async {
        return _session(
          await _dio.post<Map<String, dynamic>>('$_base/$id/$action'),
        );
      });
}

final sessionsApiProvider = Provider<SessionsApi>(
  (ref) => SessionsApi(ref.watch(dioProvider)),
);
