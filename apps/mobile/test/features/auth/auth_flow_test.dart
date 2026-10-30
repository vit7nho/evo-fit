import 'package:evofit/app/app.dart';
import 'package:evofit/app/provider_config.dart';
import 'package:evofit/core/auth/session_store.dart';
import 'package:evofit/core/network/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_server.dart';

/// App inteiro (roteador, telas, controlador e interceptor) sobre o servidor falso.
Future<FakeAuthServer> _pumpApp(
  WidgetTester tester, {
  FakeAuthServer? server,
  InMemoryTokenStorage? storage,
}) async {
  final fake = server ?? FakeAuthServer();
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [
        httpClientAdapterProvider.overrideWithValue(fake.adapter),
        tokenStorageProvider.overrideWithValue(
          storage ?? InMemoryTokenStorage(),
        ),
      ],
      child: const EvoFitApp(),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  testWidgets('sem sessão, abre no login', (tester) async {
    await _pumpApp(tester);
    expect(find.text('Entre para acompanhar sua evolução.'), findsOneWidget);
  });

  testWidgets('valida campos antes de chamar a API', (tester) async {
    final server = await _pumpApp(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe seu e-mail.'), findsOneWidget);
    expect(find.text('Informe sua senha.'), findsOneWidget);
    expect(server.adapter.requests, isEmpty);
  });

  testWidgets('senha errada mostra o erro; senha certa entra e sai', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.enterText(_field('E-mail'), FakeAuthServer.email);
    await tester.enterText(_field('Senha'), 'senha errada mas longa');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);

    // Editar o campo limpa o erro anterior (o aviso sai com animação).
    await tester.enterText(_field('Senha'), FakeAuthServer.password);
    await tester.pumpAndSettle();
    expect(find.text('E-mail ou senha incorretos.'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Olá, Ana!'), findsOneWidget);

    await tester.tap(find.byTooltip('Sair'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sair'));
    await tester.pumpAndSettle();
    expect(find.text('Entre para acompanhar sua evolução.'), findsOneWidget);
  });

  testWidgets('com sessão salva, abre direto no início', (tester) async {
    final server = FakeAuthServer(validRefreshToken: 'salvo');
    await _pumpApp(
      tester,
      server: server,
      storage: InMemoryTokenStorage('salvo'),
    );
    expect(find.text('Olá, Ana!'), findsOneWidget);
  });

  testWidgets('sem rede ao abrir, oferece nova tentativa', (tester) async {
    final server = FakeAuthServer(validRefreshToken: 'salvo')..offline = true;
    await _pumpApp(
      tester,
      server: server,
      storage: InMemoryTokenStorage('salvo'),
    );
    expect(find.text('Não foi possível conectar'), findsOneWidget);

    server.offline = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Olá, Ana!'), findsOneWidget);
  });

  group('cadastro', () {
    Future<void> openRegister(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(OutlinedButton, 'Criar conta'));
      await tester.pumpAndSettle();
    }

    Future<void> fillForm(
      WidgetTester tester, {
      required String password,
    }) async {
      await tester.enterText(_field('Como quer ser chamado'), 'Ana');
      await tester.enterText(_field('E-mail'), FakeAuthServer.email);
      await tester.enterText(_field('Senha'), password);
    }

    Future<void> acceptTerms(WidgetTester tester) async {
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
    }

    Future<void> submit(WidgetTester tester) async {
      final button = find.widgetWithText(FilledButton, 'Criar conta');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('exige o aceite dos termos', (tester) async {
      final server = await _pumpApp(tester);
      await openRegister(tester);
      await fillForm(tester, password: FakeAuthServer.password);

      await submit(tester);

      expect(
        find.text('É preciso aceitar para criar a conta.'),
        findsOneWidget,
      );
      expect(server.adapter.requests, isEmpty);
    });

    testWidgets('mostra no campo o erro devolvido pela API', (tester) async {
      await _pumpApp(tester);
      await openRegister(tester);
      await fillForm(tester, password: '1234567890');
      await acceptTerms(tester);

      await submit(tester);

      expect(
        find.text('Essa senha é muito comum. Escolha outra.'),
        findsOneWidget,
      );
    });

    testWidgets('cadastro válido entra no app', (tester) async {
      await _pumpApp(tester);
      await openRegister(tester);
      await fillForm(tester, password: FakeAuthServer.password);
      await acceptTerms(tester);

      await submit(tester);

      expect(find.text('Olá, Ana!'), findsOneWidget);
    });

    testWidgets('o resumo dos termos abre e fecha', (tester) async {
      await _pumpApp(tester);
      await openRegister(tester);

      final link = find.text('Ler o resumo dos termos');
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.text('Resumo dos termos'), findsOneWidget);

      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('Resumo dos termos'), findsNothing);
    });
  });
}
