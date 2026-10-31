import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_entrance.dart';
import '../../../shared/widgets/evo_logo.dart';
import '../../auth/application/auth_controller.dart';

/// Tela inicial de quem entrou. Ganha o painel e a navegação inferior nas próximas etapas.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).value;
    // O roteador só mostra esta tela com sessão ativa; o retorno vazio cobre a transição
    // de saída (logout), quando o estado já mudou e a tela ainda está sendo removida.
    if (auth is! Authenticated) return const Scaffold();
    final user = auth.user;
    final theme = Theme.of(context);
    // Quem pulou passos do onboarding é convidado a completar o perfil.
    final profile = user.profile;
    final incomplete =
        profile.primaryObjective == null ||
        profile.preferredModalities.isEmpty ||
        profile.weeklyAvailability == null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: EvoSpace.xl,
        title: const EvoLogo(size: 30),
        actions: [
          IconButton(
            tooltip: 'Perfil',
            onPressed: () => context.push(AppRoutes.profile),
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: EvoColors.accent,
              child: Text(
                user.displayName.isEmpty
                    ? '?'
                    : user.displayName.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: EvoColors.onAccent,
                  fontSize: EvoFontSize.bodySm,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: EvoSpace.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            EvoSpace.xl,
            EvoSpace.xl,
            EvoSpace.xl,
            EvoSpace.xl,
          ),
          children: [
            EvoEntrance(
              child: Semantics(
                header: true,
                child: Text(
                  'Olá, ${user.displayName}!',
                  style: theme.textTheme.displayMedium,
                ),
              ),
            ),
            const SizedBox(height: EvoSpace.md),
            EvoEntrance(
              delay: EvoEntrance.stagger(1),
              child: Text(
                incomplete
                    ? 'Complete seu perfil para receber sugestões que '
                          'combinam com você.'
                    : 'Tudo pronto. Metas e treinos chegam em breve.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: EvoColors.textSecondary,
                ),
              ),
            ),
            if (incomplete) ...[
              const SizedBox(height: EvoSpace.xl),
              EvoEntrance(
                delay: EvoEntrance.stagger(1),
                child: EvoButton(
                  label: 'Completar perfil',
                  trailingIcon: Icons.arrow_forward_rounded,
                  onPressed: () => context.push(AppRoutes.profile),
                ),
              ),
            ],
            const SizedBox(height: EvoSpace.x2xl),
            EvoEntrance(
              delay: EvoEntrance.stagger(2),
              child: EvoCard(
                onTap: () => context.push(AppRoutes.status),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: EvoColors.bgElevated,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.dns_outlined,
                        color: EvoColors.textPrimary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: EvoSpace.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status do servidor',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Conexão com a API e o banco de dados',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: EvoColors.textPrimary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: EvoSpace.xl),
            EvoEntrance(
              delay: EvoEntrance.stagger(3),
              child: Text(
                'Conectado como ${user.email}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
