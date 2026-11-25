import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/network/api_exception.dart';
import '../application/coach_controller.dart';
import '../domain/coach.dart';

/// Abre uma conversa nova com o assistente (geral ou com foco) a partir de qualquer
/// tela. Se a conversa não puder ser criada, avisa com a mensagem da API.
Future<void> openCoach(
  BuildContext context,
  WidgetRef ref, {
  CoachScope scope = CoachScope.global,
  Map<String, Object?>? scopeRef,
  String? title,
}) => _startConversation(
  ref.read(conversationsProvider.notifier),
  GoRouter.of(context),
  ScaffoldMessenger.of(context),
  scope: scope,
  scopeRef: scopeRef,
  title: title,
);

Future<void> _startConversation(
  ConversationsController conversations,
  GoRouter router,
  ScaffoldMessengerState messenger, {
  required CoachScope scope,
  Map<String, Object?>? scopeRef,
  String? title,
}) async {
  try {
    final conversation = await conversations.start(
      scope: scope,
      scopeRef: scopeRef,
      title: title,
    );
    unawaited(router.push(AppRoutes.coachChat(conversation.id)));
  } on ApiException catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Não foi possível abrir o assistente. ${error.message}'),
      ),
    );
  }
}

/// Botão "Perguntar à IA" dos atalhos (Meu Corpo, treino concluído).
class AskCoachButton extends ConsumerStatefulWidget {
  const AskCoachButton({
    super.key,
    required this.scope,
    required this.scopeRef,
    required this.title,
    this.closeSheet = false,
  });

  final CoachScope scope;
  final Map<String, Object?> scopeRef;
  final String title;

  /// Dentro de uma folha de baixo: fecha a folha antes de abrir a conversa.
  final bool closeSheet;

  @override
  ConsumerState<AskCoachButton> createState() => _AskCoachButtonState();
}

class _AskCoachButtonState extends ConsumerState<AskCoachButton> {
  bool _opening = false;

  Future<void> _open() async {
    setState(() => _opening = true);
    // Tudo o que a navegação precisa é lido antes: com a folha fechada, este botão
    // deixa de existir.
    final conversations = ref.read(conversationsProvider.notifier);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (widget.closeSheet) Navigator.of(context).pop();
    await _startConversation(
      conversations,
      router,
      messenger,
      scope: widget.scope,
      scopeRef: widget.scopeRef,
      title: widget.title,
    );
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _opening ? null : _open,
    icon: _opening
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.auto_awesome_outlined),
    label: const Text('Perguntar à IA'),
  );
}
