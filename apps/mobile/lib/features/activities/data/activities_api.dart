import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../history/domain/history.dart' show Paged;
import '../domain/activity.dart';

/// Corridas, caminhadas, pedais e nados (docs/API.md). Só os do dono do token.
class ActivitiesApi {
  const ActivitiesApi(this._dio);

  static const pageSize = 20;

  final Dio _dio;

  /// Da mais recente; [before] é o início da última da página anterior.
  Future<Paged<Activity>> list({String? before}) => guardApiCall(() async {
    final response = await _dio.get<List<dynamic>>(
      '/activities',
      queryParameters: {'limit': pageSize, 'before': ?before},
    );
    final items = response.data!
        .map((a) => Activity.fromJson(a as Map<String, dynamic>))
        .toList();
    // Página cheia: pode haver mais (a próxima começa antes da última desta).
    final last = items.length == pageSize ? items.last : null;
    return Paged(items, last?.startedAt.toUtc().toIso8601String());
  });

  Future<Activity> get(String id) => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>('/activities/$id');
    return Activity.fromJson(response.data!);
  });

  Future<Activity> create(Map<String, Object?> body) => guardApiCall(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/activities',
      data: body,
    );
    return Activity.fromJson(response.data!);
  });

  /// Atualização parcial: só as chaves presentes mudam; `null` limpa os opcionais.
  Future<Activity> update(String id, Map<String, Object?> changes) =>
      guardApiCall(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
          '/activities/$id',
          data: changes,
        );
        return Activity.fromJson(response.data!);
      });

  Future<void> delete(String id) =>
      guardApiCall(() => _dio.delete<void>('/activities/$id'));

  Future<ActivityOptions> options() => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>('/activity-options');
    return ActivityOptions.fromJson(response.data!);
  });
}

final activitiesApiProvider = Provider<ActivitiesApi>(
  (ref) => ActivitiesApi(ref.watch(dioProvider)),
);

/// Modalidades e rótulos. Mantidos em memória enquanto o app está aberto.
final activityOptionsProvider = FutureProvider<ActivityOptions>(
  (ref) => ref.watch(activitiesApiProvider).options(),
);
