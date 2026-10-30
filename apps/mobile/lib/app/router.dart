import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/register_page.dart';
import '../features/auth/presentation/splash_page.dart';
import '../features/home/presentation/home_page.dart';
import '../features/system_status/presentation/system_status_page.dart';
import 'routes.dart';

export 'routes.dart';

/// Decide a tela a partir da sessão. Função pura para ser testada sem widgets.
@visibleForTesting
String? authRedirect(AsyncValue<AuthState> auth, String location) {
  // O status do servidor ajuda a diagnosticar problemas de conexão em qualquer estado.
  if (location == AppRoutes.status) return null;

  final session = switch (auth) {
    AsyncData(:final value) => value,
    _ => null, // restaurando a sessão ou falha de conexão ao restaurar
  };
  if (session == null) {
    return location == AppRoutes.splash ? null : AppRoutes.splash;
  }
  final isPublic = AppRoutes.public.contains(location);
  return switch (session) {
    Unauthenticated() => isPublic ? null : AppRoutes.login,
    Authenticated() =>
      isPublic || location == AppRoutes.splash ? AppRoutes.home : null,
  };
}

final routerProvider = Provider<GoRouter>((ref) {
  // O GoRouter reavalia o redirect quando a sessão muda (login, logout, expiração).
  final authChanges = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => authChanges.value++);

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: authChanges,
    redirect: (context, state) =>
        authRedirect(ref.read(authControllerProvider), state.matchedLocation),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: AppRoutes.status,
        builder: (context, state) => const SystemStatusPage(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    authChanges.dispose();
  });
  return router;
});
