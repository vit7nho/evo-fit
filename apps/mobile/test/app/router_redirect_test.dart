import 'package:evofit/app/router.dart';
import 'package:evofit/features/auth/application/auth_controller.dart';
import 'package:evofit/features/auth/domain/current_user.dart';
import 'package:evofit/features/profile/domain/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final onboarded = DateTime.utc(2026, 10, 30);
  final user = CurrentUser(
    id: '1',
    email: 'ana@exemplo.com',
    profile: UserProfile(displayName: 'Ana', onboardingCompletedAt: onboarded),
  );
  const newUser = CurrentUser(
    id: '2',
    email: 'bia@exemplo.com',
    profile: UserProfile(displayName: 'Bia'),
  );
  const loading = AsyncLoading<AuthState>();
  final failed = AsyncError<AuthState>(Exception('sem rede'), StackTrace.empty);
  const signedOut = AsyncData<AuthState>(Unauthenticated());
  final signedIn = AsyncData<AuthState>(Authenticated(user));
  const signedInNew = AsyncData<AuthState>(Authenticated(newUser));

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

  test('conta nova vai para o onboarding antes de qualquer tela', () {
    for (final location in [
      AppRoutes.splash,
      AppRoutes.login,
      AppRoutes.home,
      AppRoutes.profile,
    ]) {
      expect(authRedirect(signedInNew, location), AppRoutes.onboarding);
    }
    expect(authRedirect(signedInNew, AppRoutes.onboarding), isNull);
  });

  test('onboarding concluído não volta para o onboarding', () {
    expect(authRedirect(signedIn, AppRoutes.onboarding), AppRoutes.home);
    expect(authRedirect(signedIn, AppRoutes.profile), isNull);
    expect(authRedirect(signedIn, AppRoutes.profileEdit('saude')), isNull);
  });

  test('status do servidor fica acessível em qualquer estado', () {
    for (final state in [loading, failed, signedOut, signedIn, signedInNew]) {
      expect(authRedirect(state, AppRoutes.status), isNull);
    }
  });
}
