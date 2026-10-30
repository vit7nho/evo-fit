import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:evofit/core/network/api_exception.dart';
import 'package:evofit/features/auth/application/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

void main() {
  late FakeAuthServer server;
  late InMemoryTokenStorage storage;

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      retry: noAutomaticRetry,
      overrides: [
        httpClientAdapterProvider.overrideWithValue(server.adapter),
        tokenStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    server = FakeAuthServer();
    storage = InMemoryTokenStorage();
  });

  group('ao abrir o app', () {
    test('sem sessão salva, pede login sem chamar a API', () async {
      final container = createContainer();

      final state = await container.read(authControllerProvider.future);

      expect(state, isA<Unauthenticated>());
      expect(server.adapter.requests, isEmpty);
    });

    test('com sessão válida salva, entra direto e rotaciona o token', () async {
      server.validRefreshToken = 'salvo';
      storage.value = 'salvo';
      final container = createContainer();

      final state = await container.read(authControllerProvider.future);

      expect(state, isA<Authenticated>());
      expect((state as Authenticated).user.displayName, 'Ana');
      expect(storage.value, isNot('salvo'));
    });

    test('com sessão salva já revogada, limpa e pede login', () async {
      storage.value = 'revogado';
      final container = createContainer();

      final state = await container.read(authControllerProvider.future);

      expect(state, isA<Unauthenticated>());
      expect(storage.value, isNull);
    });

    test(
      'sem rede, mostra erro, preserva o token e recupera ao tentar de novo',
      () async {
        server
          ..validRefreshToken = 'salvo'
          ..offline = true;
        storage.value = 'salvo';
        final container = createContainer();

        await expectLater(
          container.read(authControllerProvider.future),
          throwsA(isA<ApiException>()),
        );
        expect(storage.value, 'salvo');

        server.offline = false;
        await container.read(authControllerProvider.notifier).retryRestore();

        expect(
          container.read(authControllerProvider).value,
          isA<Authenticated>(),
        );
      },
    );
  });

  test('login guarda a sessão; logout limpa e avisa a API', () async {
    final container = createContainer();
    await container.read(authControllerProvider.future);
    final controller = container.read(authControllerProvider.notifier);

    await controller.login(
      email: FakeAuthServer.email,
      password: FakeAuthServer.password,
    );
    expect(container.read(authControllerProvider).value, isA<Authenticated>());
    expect(storage.value, isNotNull);

    await controller.logout();
    expect(
      container.read(authControllerProvider).value,
      isA<Unauthenticated>(),
    );
    expect(storage.value, isNull);
    expect(server.logoutCalls, 1);
  });

  test('login com senha errada lança a mensagem da API', () async {
    final container = createContainer();
    await container.read(authControllerProvider.future);

    await expectLater(
      container
          .read(authControllerProvider.notifier)
          .login(email: FakeAuthServer.email, password: 'errada mas longa'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'E-mail ou senha incorretos.',
        ),
      ),
    );
    expect(storage.value, isNull);
  });

  test('sessão expirada no meio do uso volta para o login', () async {
    final container = createContainer();
    await container.read(authControllerProvider.future);
    await container
        .read(authControllerProvider.notifier)
        .login(email: FakeAuthServer.email, password: FakeAuthServer.password);

    server
      ..expireAccessToken()
      ..validRefreshToken = 'revogado-em-outro-aparelho';
    await expectLater(
      container.read(dioProvider).get<void>('/me'),
      throwsA(anything),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(authControllerProvider).value,
      isA<Unauthenticated>(),
    );
  });
}
