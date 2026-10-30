import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../application/auth_controller.dart';

/// Aparece enquanto a sessão salva é restaurada, ou se a API não respondeu nesse momento.
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(EvoSpace.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'EvoFit',
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall,
              ),
              const SizedBox(height: EvoSpace.x2xl),
              if (auth.hasError)
                EvoErrorView(
                  title: 'Não foi possível conectar',
                  message: auth.error is ApiException
                      ? (auth.error! as ApiException).message
                      : 'Erro inesperado ao abrir sua sessão.',
                  onRetry: () =>
                      ref.read(authControllerProvider.notifier).retryRestore(),
                )
              else
                const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Abrindo sua sessão',
                  ),
                ),
              if (auth.hasError) ...[
                const SizedBox(height: EvoSpace.md),
                TextButton(
                  onPressed: () => context.push(AppRoutes.status),
                  child: const Text('Status do servidor'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
