import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/exercise.dart';

/// Biblioteca de exercícios (docs/API.md). O dono vem do token, nunca do corpo.
class ExercisesApi {
  const ExercisesApi(this._dio);

  final Dio _dio;

  /// Catálogo + exercícios próprios, incluindo os próprios arquivados.
  Future<List<Exercise>> list() => guardApiCall(() async {
    final response = await _dio.get<List<dynamic>>(
      '/exercises',
      queryParameters: {'include_archived': true},
    );
    return response.data!
        .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
        .toList();
  });

  Future<Exercise> create(Map<String, Object?> body) => guardApiCall(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/exercises',
      data: body,
    );
    return Exercise.fromJson(response.data!);
  });

  /// Atualização parcial de um exercício próprio; `is_active: false` arquiva.
  Future<Exercise> update(String id, Map<String, Object?> changes) =>
      guardApiCall(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
          '/exercises/$id',
          data: changes,
        );
        return Exercise.fromJson(response.data!);
      });

  Future<ExerciseOptions> options() => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>('/exercise-options');
    return ExerciseOptions.fromJson(response.data!);
  });
}

final exercisesApiProvider = Provider<ExercisesApi>(
  (ref) => ExercisesApi(ref.watch(dioProvider)),
);

/// Vocabulários da biblioteca. Mantidos em memória enquanto o app está aberto.
final exerciseOptionsProvider = FutureProvider<ExerciseOptions>(
  (ref) => ref.watch(exercisesApiProvider).options(),
);
