import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_card.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../application/coach_controller.dart';
import '../domain/coach.dart';
import 'open_coach.dart';

/// Assistente: as conversas da pessoa e o começo de uma conversa geral.
class CoachPage extends ConsumerWidget {
  const CoachPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Assistente')),
      body: SafeArea(
        top: false,
        child: conversations.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoLoadingView(lines: 4),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(EvoSpace.xl),
              child: EvoErrorView(
                title: 'Não foi possível carregar as conversas',
                message: error is ApiException
                    ? error.message
                    : 'Erro inesperado.',
                onRetry: () => ref.invalidate(conversationsProvider),
              ),
            ),
          ),
          data: (list) => ListView(
            padding: const EdgeInsets.all(EvoSpace.xl),
            children: [
              Text(
                'Pergunte sobre seus treinos, atividades, metas, alimentação, peso '
                'e o Meu Corpo. '
                'O assistente consulta os seus registros para responder.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: EvoColors.textSecondary,
                ),
              ),
              const SizedBox(height: EvoSpace.xl),
              EvoButton(
                label: 'Nova conversa',
                icon: Icons.add_comment_outlined,
                onPressed: () => openCoach(context, ref),
              ),
              const SizedBox(height: EvoSpace.x2xl),
              if (list.isEmpty)
                const EvoEmptyView(
                  icon: Icons.forum_outlined,
                  title: 'Nenhuma conversa ainda',
                  message:
                      'Comece uma conversa aqui ou use "Perguntar à IA" no '
                      'Meu Corpo e no detalhe de um treino.',
                )
              else ...[
                Semantics(
                  header: true,
                  child: Text('Conversas', style: theme.textTheme.titleLarge),
                ),
                const SizedBox(height: EvoSpace.md),
                for (final conversation in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: EvoSpace.md),
                    child: _ConversationCard(conversation: conversation),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationCard extends ConsumerWidget {
  const _ConversationCard({required this.conversation});

  final Conversation conversation;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar conversa?'),
        content: Text(
          '"${conversation.title}" e todas as mensagens serão apagadas. '
          'Não dá para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(conversationsProvider.notifier).delete(conversation.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('Conversa apagada.')),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Conversa não apagada. ${error.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final updated = conversation.updatedAt.toLocal();
    return EvoCard(
      onTap: () => context.push(AppRoutes.coachChat(conversation.id)),
      padding: const EdgeInsets.fromLTRB(
        EvoSpace.lg + 4,
        EvoSpace.md,
        EvoSpace.xs,
        EvoSpace.md,
      ),
      child: Row(
        children: [
          Icon(
            conversation.scope == CoachScope.global
                ? Icons.forum_outlined
                : Icons.center_focus_strong_outlined,
            color: EvoColors.textSecondary,
          ),
          const SizedBox(width: EvoSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conversation.title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${conversation.scope.label} · '
                  '${localizations.formatShortDate(updated)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Apagar conversa',
            onPressed: () => _delete(context, ref),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}
