import 'package:dio/dio.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/core/network/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_http_adapter.dart';

Future<ApiException> _errorFor(FakeHandler handler) async {
  final dio = dioWith(FakeHttpAdapter(handler));
  try {
    await guardApiCall(() => dio.get<Object>('/x'));
  } on ApiException catch (e) {
    return e;
  }
  fail('Era esperada uma ApiException');
}

void main() {
  test('problem+json 422 vira erro de cliente com erros por campo', () async {
    final error = await _errorFor(
      (_) => FakeHttpAdapter.json(422, {
        'status': 422,
        'code': 'validation_error',
        'detail': 'Verifique os campos informados.',
        'errors': [
          {'field': 'reps', 'message': 'Deve ser no máximo 200'},
        ],
        'request_id': 'req-1',
      }),
    );

    expect(error.kind, ApiErrorKind.client);
    expect(error.statusCode, 422);
    expect(error.code, 'validation_error');
    expect(error.message, 'Verifique os campos informados.');
    expect(error.fieldErrors, {'reps': 'Deve ser no máximo 200'});
    expect(error.requestId, 'req-1');
  });

  test('500 sem corpo usa mensagem genérica de servidor', () async {
    final error = await _errorFor((_) => ResponseBody.fromString('', 500));

    expect(error.kind, ApiErrorKind.server);
    expect(error.message, contains('servidor'));
  });

  test('falha de conexão vira erro de rede', () async {
    final error = await _errorFor(
      (options) => throw DioException.connectionError(
        requestOptions: options,
        reason: 'recusada',
      ),
    );

    expect(error.kind, ApiErrorKind.network);
    expect(error.message, contains('conectar'));
  });

  test('timeout de recebimento vira erro de timeout', () async {
    final error = await _errorFor(
      (options) => throw DioException.receiveTimeout(
        timeout: const Duration(seconds: 1),
        requestOptions: options,
      ),
    );

    expect(error.kind, ApiErrorKind.timeout);
  });
}
