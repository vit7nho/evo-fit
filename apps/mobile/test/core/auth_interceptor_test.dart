import 'package:dio/dio.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_server.dart';

void main() {
  late FakeAuthServer server;
  late InMemoryTokenStorage storage;
  late ProviderContainer container;

  setUp(() {
    server = FakeAuthServer();
    storage = InMemoryTokenStorage();
    container = ProviderContainer(
      retry: noAutomaticRetry,
      overrides: [
        httpClientAdapterProvider.overrideWithValue(server.adapter),
        tokenStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
  });

  Dio dio() => container.read(dioProvider);
  SessionStore session() => container.read(sessionStoreProvider);

  /// Entra de verdade no servidor falso e guarda os tokens na sessão.
  Future<void> signIn() async {
    final response = await dio().post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'email': FakeAuthServer.email,
        'password': FakeAuthServer.password,
      },
    );
    await session().save(AuthTokens.fromJson(response.data!));
  }

  test('anexa o access token às rotas protegidas, não às de auth', () async {
    await signIn();
    await dio().get<void>('/me');

    final requests = server.adapter.requests;
    expect(requests.first.path, '/auth/login');
    expect(requests.first.headers.containsKey('Authorization'), isFalse);
    expect(requests.last.headers['Authorization'], 'Bearer access-1');
  });

  test('em 401, renova a sessão uma vez e repete a chamada', () async {
    await signIn();
    server.expireAccessToken();

    final response = await dio().get<Map<String, dynamic>>('/me');

    expect(response.data!['email'], FakeAuthServer.email);
    expect(server.refreshCalls, 1);
    expect(session().accessToken, 'access-2');
    expect(storage.value, 'refresh-2'); // o token novo foi persistido
  });

  test(
    'várias chamadas com 401 ao mesmo tempo geram uma só renovação',
    () async {
      await signIn();
      server.expireAccessToken();

      final results = await Future.wait([
        dio().get<Map<String, dynamic>>('/me'),
        dio().get<Map<String, dynamic>>('/me'),
        dio().get<Map<String, dynamic>>('/me'),
      ]);

      expect(results.map((r) => r.statusCode), everyElement(200));
      expect(server.refreshCalls, 1);
    },
  );

  test('refresh recusado encerra a sessão e avisa a interface', () async {
    await signIn();
    server
      ..expireAccessToken()
      ..validRefreshToken = 'revogado-no-servidor';
    var expirations = 0;
    session().expirations.listen((_) => expirations++);

    await expectLater(
      dio().get<void>('/me'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          401,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(expirations, 1);
    expect(session().refreshToken, isNull);
    expect(storage.value, isNull);
  });

  test('sem rede na renovação, mantém a sessão para tentar depois', () async {
    await signIn();
    server.expireAccessToken();
    server.offline = true;

    await expectLater(
      dio().get<void>('/me'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.connectionError,
        ),
      ),
    );
    expect(storage.value, 'refresh-1');
  });
}
