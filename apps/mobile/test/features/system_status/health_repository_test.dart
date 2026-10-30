import 'package:dio/dio.dart';
import 'package:evofit/core/network/api_exception.dart';
import 'package:evofit/features/system_status/data/health_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_http_adapter.dart';

void main() {
  test('200 com banco ok é interpretado como saudável', () async {
    final adapter = FakeHttpAdapter(
      (_) => FakeHttpAdapter.json(200, {
        'status': 'ok',
        'database': 'ok',
        'version': '0.1.0',
        'environment': 'development',
      }),
    );

    final status = await HealthRepository(dioWith(adapter)).fetch();

    expect(adapter.requests.single.path, '/health');
    expect(status.databaseOk, isTrue);
    expect(status.version, '0.1.0');
    expect(status.environment, 'development');
  });

  test(
    '503 traz o corpo de saúde com banco indisponível, sem lançar',
    () async {
      final adapter = FakeHttpAdapter(
        (_) => FakeHttpAdapter.json(503, {
          'status': 'degraded',
          'database': 'unavailable',
          'version': '0.1.0',
          'environment': 'development',
        }),
      );

      final status = await HealthRepository(dioWith(adapter)).fetch();

      expect(status.databaseOk, isFalse);
    },
  );

  test('API inacessível lança ApiException de rede', () async {
    final adapter = FakeHttpAdapter(
      (options) => throw DioException.connectionError(
        requestOptions: options,
        reason: 'recusada',
      ),
    );

    expect(
      HealthRepository(dioWith(adapter)).fetch(),
      throwsA(
        isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.network),
      ),
    );
  });
}
