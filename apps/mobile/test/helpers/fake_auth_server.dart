import 'package:dio/dio.dart';
import 'package:evofit/core/auth/session_store.dart';

import 'fake_http_adapter.dart';

/// Armazenamento de tokens em memória (o Keystore não existe nos testes).
class InMemoryTokenStorage implements TokenStorage {
  InMemoryTokenStorage([this.value]);

  String? value;

  @override
  Future<String?> readRefreshToken() async => value;

  @override
  Future<void> writeRefreshToken(String token) async => value = token;

  @override
  Future<void> clear() async => value = null;
}

/// Imitação da API de autenticação com as mesmas regras de tokens do backend:
/// cada login/refresh gera um par novo e invalida o anterior.
class FakeAuthServer {
  FakeAuthServer({this.validRefreshToken});

  static const email = 'ana@exemplo.com';
  static const password = 'cavalo bateria grampo';

  late final adapter = FakeHttpAdapter(_handle);

  String? validAccessToken;
  String? validRefreshToken;
  bool offline = false;
  int refreshCalls = 0;
  int logoutCalls = 0;
  int _counter = 0;

  /// Faz o access token atual expirar (o próximo uso recebe 401).
  void expireAccessToken() => validAccessToken = 'expirado';

  ResponseBody _handle(RequestOptions options) {
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'sem rede (teste)',
      );
    }
    final body = options.data is Map ? options.data as Map : const {};
    return switch ((options.method, options.path)) {
      ('POST', '/auth/login') =>
        body['email'] == email && body['password'] == password
            ? _issueTokens()
            : _problem(
                401,
                'invalid_credentials',
                'E-mail ou senha incorretos.',
              ),
      ('POST', '/auth/register') =>
        body['password'] == '1234567890'
            ? _problem(
                422,
                'validation_error',
                'Verifique os campos informados.',
                errors: [
                  {
                    'field': 'password',
                    'message': 'Essa senha é muito comum. Escolha outra.',
                  },
                ],
              )
            : _issueTokens(),
      ('POST', '/auth/refresh') => _refresh(body['refresh_token']),
      ('POST', '/auth/logout') => _logout(),
      ('GET', '/me') =>
        options.headers['Authorization'] == 'Bearer $validAccessToken'
            ? FakeHttpAdapter.json(200, {
                'id': '0192f0c0-0000-7000-8000-000000000001',
                'email': email,
                'status': 'active',
                'created_at': '2026-10-30T12:00:00Z',
                'profile': {'display_name': 'Ana'},
                'consents': <Object>[],
              })
            : _problem(401, 'invalid_token', 'Sessão inválida ou expirada.'),
      ('GET', '/health') => FakeHttpAdapter.json(200, {
        'status': 'ok',
        'database': 'ok',
        'version': '0.1.0',
        'environment': 'test',
      }),
      _ => _problem(404, 'not_found', 'Rota não encontrada no servidor falso.'),
    };
  }

  ResponseBody _refresh(Object? token) {
    refreshCalls++;
    if (token == null || token != validRefreshToken) {
      return _problem(401, 'invalid_refresh_token', 'Sessão expirada.');
    }
    return _issueTokens();
  }

  ResponseBody _logout() {
    logoutCalls++;
    validRefreshToken = null;
    return ResponseBody.fromString('', 204);
  }

  ResponseBody _issueTokens() {
    _counter++;
    validAccessToken = 'access-$_counter';
    validRefreshToken = 'refresh-$_counter';
    return FakeHttpAdapter.json(200, {
      'access_token': validAccessToken,
      'refresh_token': validRefreshToken,
      'token_type': 'bearer',
      'expires_in': 900,
      'refresh_expires_in': 2592000,
    });
  }

  static ResponseBody _problem(
    int status,
    String code,
    String detail, {
    List<Map<String, String>> errors = const [],
  }) => FakeHttpAdapter.json(status, {
    'type': 'https://evofit.local/errors/$code',
    'title': 'Erro',
    'status': status,
    'code': code,
    'detail': detail,
    'errors': errors,
    'request_id': 'teste',
  });
}
