import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../analytics/domain/analytics.dart' show apiDate;
import '../../nutrition/data/nutrition_api.dart' show localDateTime;
import '../domain/measurements.dart';

/// Peso e medidas (docs/API.md §Fase 5).
class MeasurementsApi {
  const MeasurementsApi(this._dio);

  final Dio _dio;

  Future<List<MetricInfo>> options() => guardApiCall(() async {
    final response = await _dio.get<List<dynamic>>('/body-measurement-options');
    return [
      for (final o in response.data!)
        MetricInfo.fromJson(o as Map<String, dynamic>),
    ];
  });

  /// Do dia [from] até hoje (no fuso do perfil).
  Future<List<Measurement>> list(DateTime from) => guardApiCall(() async {
    final response = await _dio.get<List<dynamic>>(
      '/body-measurements',
      queryParameters: {'from': apiDate(from)},
    );
    return [
      for (final m in response.data!)
        Measurement.fromJson(m as Map<String, dynamic>),
    ];
  });

  Future<Trend> trend(String metric, DateTime from) => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/body-measurements/trend',
      queryParameters: {'metric': metric, 'from': apiDate(from)},
    );
    return Trend.fromJson(response.data!);
  });

  /// Cria ([id] nulo) ou altera. Na alteração, as medidas que não estão em
  /// [values] são limpas.
  Future<Measurement> save({
    String? id,
    required DateTime measuredAt,
    required Map<String, double> values,
    String? notes,
  }) => guardApiCall(() async {
    final body = {
      // Em UTC: o instante (o "agora" do aparelho, certo em qualquer fuso). Sem
      // fuso: o horário escolhido, no fuso do perfil (como nas refeições).
      'measured_at': measuredAt.isUtc
          ? measuredAt.toIso8601String()
          : localDateTime(measuredAt),
      for (final metric in metricOrder) metric: values[metric],
      'notes': notes,
    };
    final response = id == null
        ? await _dio.post<Map<String, dynamic>>(
            '/body-measurements',
            data: body,
          )
        : await _dio.patch<Map<String, dynamic>>(
            '/body-measurements/$id',
            data: body,
          );
    return Measurement.fromJson(response.data!);
  });

  Future<void> delete(String id) =>
      guardApiCall(() => _dio.delete<void>('/body-measurements/$id'));
}

final measurementsApiProvider = Provider<MeasurementsApi>(
  (ref) => MeasurementsApi(ref.watch(dioProvider)),
);
