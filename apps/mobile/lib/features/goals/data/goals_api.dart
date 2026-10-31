import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/goal.dart';

/// Metas do usuário (docs/API.md). O dono vem do token, nunca do corpo.
class GoalsApi {
  const GoalsApi(this._dio);

  final Dio _dio;

  Future<List<Goal>> list() => guardApiCall(() async {
    final response = await _dio.get<List<dynamic>>('/goals');
    return response.data!
        .map((g) => Goal.fromJson(g as Map<String, dynamic>))
        .toList();
  });

  Future<Goal> create(Map<String, Object?> body) => guardApiCall(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/goals',
      data: body,
    );
    return Goal.fromJson(response.data!);
  });

  /// Atualização parcial: só as chaves presentes mudam; `null` limpa o prazo.
  Future<Goal> update(String id, Map<String, Object?> changes) =>
      guardApiCall(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
          '/goals/$id',
          data: changes,
        );
        return Goal.fromJson(response.data!);
      });

  Future<void> delete(String id) =>
      guardApiCall(() => _dio.delete<void>('/goals/$id'));

  Future<GoalOptions> options() => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>('/goal-options');
    return GoalOptions.fromJson(response.data!);
  });
}

final goalsApiProvider = Provider<GoalsApi>(
  (ref) => GoalsApi(ref.watch(dioProvider)),
);

/// Tipos de meta e rótulos. Mantidos em memória enquanto o app está aberto.
final goalOptionsProvider = FutureProvider<GoalOptions>(
  (ref) => ref.watch(goalsApiProvider).options(),
);
