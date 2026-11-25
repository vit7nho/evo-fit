import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/auth_controller.dart';
import '../data/coach_api.dart';
import '../domain/coach.dart';

/// Id da conta logada: ao sair ou trocar de conta, as conversas são descartadas e as
/// de uma pessoa nunca aparecem para outra.
String? _userId(Ref ref) => ref.watch(
  authControllerProvider.select(
    (auth) => switch (auth.value) {
      Authenticated(:final user) => user.id,
      _ => null,
    },
  ),
);

/// Conversas da pessoa, da mais recente.
class ConversationsController extends AsyncNotifier<List<Conversation>> {
  CoachApi get _api => ref.read(coachApiProvider);

  @override
  Future<List<Conversation>> build() async {
    if (_userId(ref) == null) return const [];
    return ref.watch(coachApiProvider).list();
  }

  /// Cria a conversa (geral ou com foco) e devolve para a tela abrir.
  Future<Conversation> start({
    CoachScope scope = CoachScope.global,
    Map<String, Object?>? scopeRef,
    String? title,
  }) async {
    final conversation = await _api.create(
      scope: scope,
      scopeRef: scopeRef,
      title: title,
    );
    ref.invalidateSelf();
    return conversation;
  }

  Future<void> delete(String id) async {
    await _api.delete(id);
    final current = state.value;
    if (current != null) {
      state = AsyncData([
        for (final c in current)
          if (c.id != id) c,
      ]);
    }
    ref.invalidate(chatProvider(id));
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsController, List<Conversation>>(
      ConversationsController.new,
    );

/// Uma conversa aberta: as mensagens, a pergunta em andamento e a cota do dia.
class ChatController extends AsyncNotifier<ChatState> {
  ChatController(this.conversationId);

  final String conversationId;
  CoachApi get _api => ref.read(coachApiProvider);

  @override
  Future<ChatState> build() async {
    _userId(ref);
    final (conversation, messages) = await ref
        .watch(coachApiProvider)
        .get(conversationId);
    return ChatState(conversation: conversation, messages: messages);
  }

  /// Envia a pergunta. Enquanto a IA responde, ela aparece como pendente; se falhar,
  /// some da conversa (o servidor não a grava) e o erro sobe para a tela, que devolve
  /// o texto ao campo para a pessoa tentar de novo.
  Future<void> ask(String question) async {
    final current = state.value;
    if (current == null || current.sending) return;
    state = AsyncData(current.copyWith(pending: () => question));
    try {
      final reply = await _api.ask(conversationId, question);
      final now = state.value ?? current;
      state = AsyncData(
        now.copyWith(
          messages: [...now.messages, reply.question, reply.answer],
          pending: () => null,
          simulated: reply.simulated,
          remainingToday: reply.remainingToday,
        ),
      );
      // A lista mostra a conversa no topo, com o título novo.
      ref.invalidate(conversationsProvider);
    } on ApiException {
      final now = state.value ?? current;
      state = AsyncData(now.copyWith(pending: () => null));
      rethrow;
    }
  }
}

final chatProvider =
    AsyncNotifierProvider.family<ChatController, ChatState, String>(
      ChatController.new,
    );
