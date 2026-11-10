import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/analytics.dart';

/// Indicadores calculados pela API (docs/API.md), só com os dados do dono do token.
class AnalyticsApi {
  const AnalyticsApi(this._dio);

  final Dio _dio;

  Future<Overview> overview(AnalyticsPeriod period) => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/analytics/overview',
      queryParameters: {'from': apiDate(period.from), 'to': apiDate(period.to)},
    );
    return Overview.fromJson(response.data!);
  });

  Future<EnduranceSummary> endurance(AnalyticsPeriod period, String modality) =>
      guardApiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/analytics/endurance',
          queryParameters: {
            'modality': modality,
            'from': apiDate(period.from),
            'to': apiDate(period.to),
          },
        );
        return EnduranceSummary.fromJson(response.data!);
      });

  /// [metric] no período atual comparado com o anterior, do mesmo tamanho.
  Future<Comparison> compareWithPrevious(
    AnalyticsPeriod period,
    String metric, {
    String? modality,
  }) => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/analytics/compare',
      queryParameters: {
        'metric': metric,
        'modality': ?modality,
        'a_from': apiDate(period.previousFrom),
        'a_to': apiDate(period.previousTo),
        'b_from': apiDate(period.from),
        'b_to': apiDate(period.to),
      },
    );
    return Comparison.fromJson(response.data!);
  });
}

final analyticsApiProvider = Provider<AnalyticsApi>(
  (ref) => AnalyticsApi(ref.watch(dioProvider)),
);
