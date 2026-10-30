import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../shared/widgets/evo_card.dart';
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: EvoColors.bgBase,
        title: const Text('EvoFit'),
        actions: [
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => _confirmLogout(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(EvoSpace.xl),
          children: [
            Text(
              'Olá, ${user.displayName}!',
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: EvoSpace.sm),
            Text(
              'Sua conta está pronta. Perfil, metas e treinos chegam nas '
              'próximas etapas do projeto.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: EvoColors.textSecondary,
              ),
            ),
            const SizedBox(height: EvoSpace.x2xl),
            EvoCard(
              onTap: () => context.push(AppRoutes.status),
              child: Row(
                children: [
                  const Icon(Icons.dns_outlined, color: EvoColors.accent),
                  const SizedBox(width: EvoSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status do servidor',
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          'Conexão com a API e o banco de dados',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: EvoColors.textSecondary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: EvoSpace.lg),
            Text(
              'Conectado como ${user.email}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text(
          'Você precisará entrar de novo com e-mail e senha neste aparelho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}
