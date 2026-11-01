import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/register_page.dart';
import '../features/auth/presentation/splash_page.dart';
import '../features/exercises/presentation/exercise_detail_page.dart';
import '../features/exercises/presentation/exercise_form_page.dart';
import '../features/exercises/presentation/exercises_page.dart';
import '../features/goals/presentation/goal_form_page.dart';
import '../features/goals/presentation/goals_page.dart';
import '../features/goals/presentation/new_goal_page.dart';
import '../features/home/presentation/home_page.dart';
import '../features/profile/presentation/edit_profile_section_page.dart';
import '../features/profile/presentation/onboarding_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/profile/presentation/profile_sections.dart';
import '../features/sessions/presentation/session_page.dart';
import '../features/system_status/presentation/system_status_page.dart';
import '../features/training/presentation/template_editor_page.dart';
import '../features/training/presentation/templates_page.dart';
import 'routes.dart';
import 'theme/motion.dart';
import 'theme/tokens.g.dart';

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
    // Conta nova: o onboarding vem antes de qualquer outra tela.
    Authenticated(:final user) when user.needsOnboarding =>
      location == AppRoutes.onboarding ? null : AppRoutes.onboarding,
    Authenticated() =>
      isPublic ||
              location == AppRoutes.splash ||
              location == AppRoutes.onboarding
          ? AppRoutes.home
          : null,
  };
}

/// Resumo do estado da sessão que importa para o roteamento.
Object _routeRelevantState(AsyncValue<AuthState> auth) => switch (auth) {
  AsyncData(value: Authenticated(:final user)) => (
    'authenticated',
    user.needsOnboarding,
  ),
  AsyncData(value: Unauthenticated()) => 'unauthenticated',
  AsyncError() => 'error',
  _ => 'loading',
};

/// Página com a transição padrão do app (sobe e aparece; a anterior recua).
CustomTransitionPage<void> _page(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: EvoMotion.page,
      reverseTransitionDuration: EvoMotion.base,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          EvoPageTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            child: child,
          ),
    );

final routerProvider = Provider<GoRouter>((ref) {
  // O GoRouter reavalia o redirect só quando muda o que decide a rota (entrou, saiu,
  // expirou, concluiu o onboarding). Salvar o perfil não deve mexer na navegação.
  final authChanges = ValueNotifier<int>(0);
  ref.listen(
    authControllerProvider.select(_routeRelevantState),
    (_, _) => authChanges.value++,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: authChanges,
    redirect: (context, state) =>
        authRedirect(ref.read(authControllerProvider), state.matchedLocation),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (context, state) => _page(state, const SplashPage()),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) => _page(state, const LoginPage()),
      ),
      GoRoute(
        path: AppRoutes.register,
        pageBuilder: (context, state) => _page(state, const RegisterPage()),
      ),
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (context, state) => _page(state, const HomePage()),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => _page(state, const OnboardingPage()),
      ),
      GoRoute(
        path: AppRoutes.profile,
        pageBuilder: (context, state) => _page(state, const ProfilePage()),
        routes: [
          GoRoute(
            path: ':section',
            pageBuilder: (context, state) => _page(
              state,
              EditProfileSectionPage(
                section: ProfileSection.fromPath(
                  state.pathParameters['section']!,
                ),
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.exercises,
        pageBuilder: (context, state) => _page(state, const ExercisesPage()),
        routes: [
          // "novo" antes de ":id": o caminho literal tem precedência.
          GoRoute(
            path: 'novo',
            pageBuilder: (context, state) =>
                _page(state, const ExerciseFormPage.create()),
          ),
          GoRoute(
            path: ':id',
            pageBuilder: (context, state) => _page(
              state,
              ExerciseDetailPage(exerciseId: state.pathParameters['id']!),
            ),
            routes: [
              GoRoute(
                path: 'editar',
                pageBuilder: (context, state) => _page(
                  state,
                  ExerciseFormPage.edit(
                    exerciseId: state.pathParameters['id']!,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.session,
        pageBuilder: (context, state) => _page(state, const SessionPage()),
      ),
      GoRoute(
        path: AppRoutes.templates,
        pageBuilder: (context, state) => _page(state, const TemplatesPage()),
        routes: [
          // "nova" antes de ":id": o caminho literal tem precedência.
          GoRoute(
            path: 'nova',
            pageBuilder: (context, state) =>
                _page(state, const TemplateEditorPage.create()),
          ),
          GoRoute(
            path: ':id',
            pageBuilder: (context, state) => _page(
              state,
              TemplateEditorPage.edit(templateId: state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.goals,
        pageBuilder: (context, state) => _page(state, const GoalsPage()),
        routes: [
          // "nova" antes de ":id": o caminho literal tem precedência.
          GoRoute(
            path: 'nova',
            pageBuilder: (context, state) => _page(state, const NewGoalPage()),
            routes: [
              GoRoute(
                path: ':kind',
                pageBuilder: (context, state) => _page(
                  state,
                  GoalFormPage.create(kind: state.pathParameters['kind']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: ':id',
            pageBuilder: (context, state) => _page(
              state,
              GoalFormPage.edit(goalId: state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.status,
        pageBuilder: (context, state) => _page(state, const SystemStatusPage()),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    authChanges.dispose();
  });
  return router;
});
