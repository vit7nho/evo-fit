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
import '../../goals/application/goals_controller.dart';
import '../../goals/domain/goal.dart';

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
    final goals = ref.watch(goalsProvider);
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
                    : 'Tudo pronto. Os treinos chegam em breve.',
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
              child: _LinkCard(
                icon: Icons.flag_outlined,
                title: 'Metas',
                subtitle: switch (goals) {
                  AsyncData(:final value) => _goalsSummary(value),
                  AsyncError() => 'Não foi possível carregar. Toque para ver.',
                  _ => 'Carregando…',
                },
                onTap: () => context.push(AppRoutes.goals),
              ),
            ),
            const SizedBox(height: EvoSpace.md),
            EvoEntrance(
              delay: EvoEntrance.stagger(3),
              child: _LinkCard(
                icon: Icons.dns_outlined,
                title: 'Status do servidor',
                subtitle: 'Conexão com a API e o banco de dados',
                onTap: () => context.push(AppRoutes.status),
              ),
            ),
            const SizedBox(height: EvoSpace.xl),
            EvoEntrance(
              delay: EvoEntrance.stagger(4),
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

  static String _goalsSummary(List<Goal> goals) {
    final active = goals.where((g) => g.isActive).length;
    return switch (active) {
      0 => 'Defina o que quer alcançar',
      1 => '1 meta ativa',
      _ => '$active metas ativas',
    };
  }
}

/// Cartão de atalho do início: ícone, título, resumo e seta.
class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvoCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: EvoColors.bgElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: EvoColors.textPrimary, size: 22),
          ),
          const SizedBox(width: EvoSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodyMedium),
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
    );
  }
}
