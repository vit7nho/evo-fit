import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_entrance.dart';
import '../../../shared/widgets/evo_logo.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../application/auth_controller.dart';

/// Aparece enquanto a sessão salva é restaurada, ou se a API não respondeu nesse momento.
///
/// Mesmo fundo da abertura nativa do Android: a troca para o Flutter não pisca.
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(EvoSpace.xl),
          child: Column(
            children: [
              const Spacer(flex: 3),
              const _LogoReveal(),
              const SizedBox(height: EvoSpace.x2xl),
              // Some no erro (e sai da árvore: uma barra indeterminada anima sem parar).
              SizedBox(
                height: 4,
                width: 96,
                child: auth.hasError
                    ? null
                    : const ClipRRect(
                        borderRadius: BorderRadius.all(
                          Radius.circular(EvoRadius.pill),
                        ),
                        child: LinearProgressIndicator(
                          semanticsLabel: 'Abrindo sua sessão',
                        ),
                      ),
              ),
              const Spacer(flex: 2),
              AnimatedSwitcher(
                duration: EvoMotion.base,
                child: auth.hasError
                    ? EvoEntrance(
                        child: Column(
                          children: [
                            EvoErrorView(
                              title: 'Não foi possível conectar',
                              message: auth.error is ApiException
                                  ? (auth.error! as ApiException).message
                                  : 'Erro inesperado ao abrir sua sessão.',
                              onRetry: () => ref
                                  .read(authControllerProvider.notifier)
                                  .retryRestore(),
                            ),
                            const SizedBox(height: EvoSpace.sm),
                            TextButton(
                              onPressed: () => context.push(AppRoutes.status),
                              style: TextButton.styleFrom(
                                foregroundColor: EvoColors.textSecondary,
                              ),
                              child: const Text('Status do servidor'),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(height: EvoSpace.x3xl),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoReveal extends StatelessWidget {
  const _LogoReveal();

  @override
  Widget build(BuildContext context) {
    const logo = EvoLogo(size: 52);
    if (MediaQuery.of(context).disableAnimations) return logo;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: EvoMotion.page,
      curve: EvoCurves.emphasizedDecelerate,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
      ),
      child: logo,
    );
  }
}
