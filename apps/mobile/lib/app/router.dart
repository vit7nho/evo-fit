import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/system_status/presentation/system_status_page.dart';

abstract final class AppRoutes {
  static const status = '/';
}

/// Rotas do app. Na Fase 2 entram autenticação (redirect) e a navegação inferior.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.status,
    routes: [
      GoRoute(
        path: AppRoutes.status,
        builder: (context, state) => const SystemStatusPage(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
