import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/template.dart';

/// Fichas de treino (docs/API.md). A ficha é enviada inteira a cada salvamento.
class TemplatesApi {
  const TemplatesApi(this._dio);

  final Dio _dio;

  Future<List<WorkoutTemplate>> list() => guardApiCall(() async {
    final response = await _dio.get<List<dynamic>>('/workout-templates');
    return _templates(response.data!);
  });

  Future<WorkoutTemplate> create(Map<String, Object?> body) =>
      guardApiCall(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/workout-templates',
          data: body,
        );
        return WorkoutTemplate.fromJson(response.data!);
      });

  Future<WorkoutTemplate> replace(String id, Map<String, Object?> body) =>
      guardApiCall(() async {
        final response = await _dio.put<Map<String, dynamic>>(
          '/workout-templates/$id',
          data: body,
        );
        return WorkoutTemplate.fromJson(response.data!);
      });

  Future<void> delete(String id) =>
      guardApiCall(() => _dio.delete<void>('/workout-templates/$id'));

  Future<List<WorkoutTemplate>> reorder(List<String> ids) =>
      guardApiCall(() async {
        final response = await _dio.put<List<dynamic>>(
          '/workout-templates/order',
          data: {'template_ids': ids},
        );
        return _templates(response.data!);
      });

  Future<WorkoutOptions> options() => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>('/workout-options');
    return WorkoutOptions.fromJson(response.data!);
  });

  static List<WorkoutTemplate> _templates(List<dynamic> data) => data
      .map((t) => WorkoutTemplate.fromJson(t as Map<String, dynamic>))
      .toList();
}

final templatesApiProvider = Provider<TemplatesApi>(
  (ref) => TemplatesApi(ref.watch(dioProvider)),
);

/// Tipos de agrupamento e de série. Mantidos em memória enquanto o app está aberto.
final workoutOptionsProvider = FutureProvider<WorkoutOptions>(
  (ref) => ref.watch(templatesApiProvider).options(),
);
