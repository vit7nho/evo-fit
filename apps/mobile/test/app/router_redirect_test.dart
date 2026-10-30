import 'package:evofit/app/router.dart';
import 'package:evofit/features/auth/application/auth_controller.dart';
import 'package:evofit/features/auth/domain/current_user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const user = CurrentUser(
    id: '1',
    email: 'ana@exemplo.com',
    displayName: 'Ana',
  );
  const loading = AsyncLoading<AuthState>();
  final failed = AsyncError<AuthState>(Exception('sem rede'), StackTrace.empty);
  const signedOut = AsyncData<AuthState>(Unauthenticated());
  const signedIn = AsyncData<AuthState>(Authenticated(user));

  test('restaurando ou com falha de conexão: fica na abertura', () {
    for (final state in [loading, failed]) {
      expect(authRedirect(state, AppRoutes.splash), isNull);
      expect(authRedirect(state, AppRoutes.home), AppRoutes.splash);
      expect(authRedirect(state, AppRoutes.login), AppRoutes.splash);
    }
  });

  test('sem sessão: só login e cadastro', () {
    expect(authRedirect(signedOut, AppRoutes.splash), AppRoutes.login);
    expect(authRedirect(signedOut, AppRoutes.home), AppRoutes.login);
    expect(authRedirect(signedOut, AppRoutes.login), isNull);
    expect(authRedirect(signedOut, AppRoutes.register), isNull);
  });

  test('com sessão: telas públicas e abertura levam ao início', () {
    expect(authRedirect(signedIn, AppRoutes.splash), AppRoutes.home);
    expect(authRedirect(signedIn, AppRoutes.login), AppRoutes.home);
    expect(authRedirect(signedIn, AppRoutes.register), AppRoutes.home);
    expect(authRedirect(signedIn, AppRoutes.home), isNull);
  });

  test('status do servidor fica acessível em qualquer estado', () {
    for (final state in [loading, failed, signedOut, signedIn]) {
      expect(authRedirect(state, AppRoutes.status), isNull);
    }
  });
}
