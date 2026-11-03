import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/history.dart';

/// Histórico e recordes (docs/API.md). Só o que é do dono do token.
class HistoryApi {
  const HistoryApi(this._dio);

  final Dio _dio;

  /// Treinos concluídos, do mais recente; [before] é o cursor da página anterior.
  Future<Paged<SessionSummary>> sessions({String? before}) =>
      guardApiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/workout-sessions',
          queryParameters: {'limit': 20, 'before': ?before},
        );
        final data = response.data!;
        return Paged(
          (data['items'] as List<dynamic>)
              .map((s) => SessionSummary.fromJson(s as Map<String, dynamic>))
              .toList(),
          data['next_before'] as String?,
        );
      });

  Future<ExerciseHistory> exercise(String exerciseId, {String? before}) =>
      guardApiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/exercises/$exerciseId/history',
          queryParameters: {'limit': 10, 'before': ?before},
        );
        return ExerciseHistory.fromJson(response.data!);
      });

  Future<List<ExerciseRecords>> records() => guardApiCall(() async {
    final response = await _dio.get<List<dynamic>>('/analytics/records');
    return response.data!
        .map((r) => ExerciseRecords.fromJson(r as Map<String, dynamic>))
        .toList();
  });
}

final historyApiProvider = Provider<HistoryApi>(
  (ref) => HistoryApi(ref.watch(dioProvider)),
);
