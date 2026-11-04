import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/plan.dart';

/// Planos de caminhada, 5 km e 10 km (docs/API.md). Só os do dono do token.
class PlansApi {
  const PlansApi(this._dio);

  final Dio _dio;

  Future<List<PlanTemplate>> templates() => guardApiCall(() async {
    final response = await _dio.get<List<dynamic>>('/training-plan-templates');
    return response.data!
        .map((t) => PlanTemplate.fromJson(t as Map<String, dynamic>))
        .toList();
  });

  /// Do mais recente; sem as sessões.
  Future<List<TrainingPlan>> list() => guardApiCall(() async {
    final response = await _dio.get<List<dynamic>>('/training-plans');
    return response.data!
        .map((p) => TrainingPlan.fromJson(p as Map<String, dynamic>))
        .toList();
  });

  Future<TrainingPlan> get(String id) =>
      _plan(() => _dio.get('/training-plans/$id'));

  Future<TrainingPlan> create({
    required String kind,
    required List<int> weekdays,
    required DateTime startDate,
  }) => _plan(
    () => _dio.post(
      '/training-plans',
      data: {
        'kind': kind,
        'weekdays': weekdays,
        'start_date': _date(startDate),
      },
    ),
  );

  Future<TrainingPlan> end(String id) =>
      _plan(() => _dio.post('/training-plans/$id/end'));

  /// Marca a sessão como feita com uma atividade registrada.
  Future<TrainingPlan> link(
    String planId,
    String sessionId,
    String activityId,
  ) => _plan(
    () => _dio.put(
      '/training-plans/$planId/sessions/$sessionId/activity',
      data: {'activity_id': activityId},
    ),
  );

  Future<TrainingPlan> unlink(String planId, String sessionId) => _plan(
    () => _dio.delete('/training-plans/$planId/sessions/$sessionId/activity'),
  );

  Future<TrainingPlan> _plan(
    Future<Response<Map<String, dynamic>>> Function() call,
  ) => guardApiCall(() async => TrainingPlan.fromJson((await call()).data!));

  static String _date(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

final plansApiProvider = Provider<PlansApi>(
  (ref) => PlansApi(ref.watch(dioProvider)),
);
