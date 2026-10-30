import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/health_status.dart';

class HealthRepository {
  const HealthRepository(this._dio);

  final Dio _dio;

  Future<HealthStatus> fetch() => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/health',
      // 503 também traz o corpo de saúde (banco indisponível); não é erro de transporte.
      options: Options(validateStatus: (s) => s == 200 || s == 503),
    );
    return HealthStatus.fromJson(response.data ?? const {});
  });
}

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => HealthRepository(ref.watch(dioProvider)),
);
