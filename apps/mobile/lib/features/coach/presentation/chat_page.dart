import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/evo_button.dart';
import '../../../shared/widgets/evo_state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../profile/application/profile_actions.dart';
import '../../profile/domain/profile.dart';
import '../application/coach_controller.dart';
import '../domain/coach.dart';
import 'open_coach.dart';
import 'proposal_card.dart';

/// Uma conversa com o assistente: mensagens, perguntas sugeridas e o campo de envio.
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  /// Pergunta máxima aceita pela API.
  static const maxChars = 2000;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggestion]) async {
    final text = (suggestion ?? _input.text).trim();
    if (text.isEmpty) return;
    setState(() => _error = null);
    _input.clear();
    try {
      await ref.read(chatProvider(widget.conversationId).notifier).ask(text);
      if (!mounted) return;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Resposta recebida.',
          TextDirection.ltr,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      // A pergunta volta ao campo: dá para tentar de novo sem redigitar.
      _input.text = text;
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider(widget.conversationId));
    final auth = ref.watch(authControllerProvider).value;
    final consented =
        auth is Authenticated &&
        auth.user.hasConsent(ConsentKinds.aiProcessing);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          chat.value?.conversation.title ?? 'Assistente',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: chat.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(EvoSpace.xl),
            child: EvoLoadingView(lines: 4),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(EvoSpace.xl),
              child: EvoErrorView(
                title: 'Não foi possível abrir a conversa',
                message: error is ApiException
                    ? error.message
                    : 'Erro inesperado.',
                onRetry: () =>
                    ref.invalidate(chatProvider(widget.conversationId)),
              ),
            ),
          ),
          data: (state) => Column(
            children: [
              Expanded(
                child: _Messages(state: state, onSuggestion: _send),
              ),
              if (!consented)
                const _ConsentCard()
              else
                _Composer(
                  controller: _input,
                  focusNode: _focus,
                  sending: state.sending,
                  error: _error,
                  remainingToday: state.remainingToday,
                  onSend: _send,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Messages extends StatelessWidget {
  const _Messages({required this.state, required this.onSuggestion});

  final ChatState state;
  final void Function(String) onSuggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversation = state.conversation;
    // A lista cresce de baixo para cima: a mensagem mais nova fica sempre à vista.
    final items = <Widget>[
      _Header(conversation: conversation),
      if (state.messages.isEmpty && !state.sending)
        _Suggestions(
          suggestions: suggestionsFor(conversation.scope),
          onTap: onSuggestion,
        ),
      for (final message in state.messages) ...[
        _Bubble(message: message),
        for (final proposal in message.proposals)
          ProposalCard(conversationId: conversation.id, proposal: proposal),
      ],
      if (state.pending case final question?) ...[
        _Bubble(
          message: ChatMessage(
            id: 'pendente',
            fromUser: true,
            content: question,
          ),
        ),
        const _Thinking(),
      ],
      if (state.simulated)
        Padding(
          padding: const EdgeInsets.only(top: EvoSpace.sm),
          child: Text(
            'Modo de demonstração: a IA de verdade ainda não está ligada neste '
            'servidor, e as respostas são simuladas.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: EvoColors.warning,
            ),
          ),
        ),
    ];
    return ListView(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(
        EvoSpace.xl,
        EvoSpace.lg,
        EvoSpace.xl,
        EvoSpace.lg,
      ),
      children: [
        for (final item in items.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: EvoSpace.md),
            child: item,
          ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final specific = conversation.scope != CoachScope.global;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: EvoSpace.sm,
          runSpacing: EvoSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              avatar: Icon(
                specific
                    ? Icons.center_focus_strong_outlined
                    : Icons.forum_outlined,
                size: 18,
              ),
              label: Text(conversation.scope.label),
            ),
            // Trocar de modo abre outra conversa: o contexto de cada uma fica
            // limpo e explícito (AI_DESIGN §4).
            if (specific)
              TextButton.icon(
                onPressed: () => openCoach(context, ref),
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('Perguntar sobre tudo'),
              ),
          ],
        ),
        const SizedBox(height: EvoSpace.sm),
        Text(
          'As respostas usam só os seus registros e podem conter erros. '
          'Não substituem orientação de um profissional de saúde.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: EvoColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.suggestions, required this.onTap});

  final List<String> suggestions;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text('Comece por aqui', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: EvoSpace.sm),
        for (final suggestion in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: EvoSpace.sm),
            child: ActionChip(
              label: Text(suggestion),
              onPressed: () => onTap(suggestion),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromUser = message.fromUser;
    final tools = describeTools(message.toolsUsed);
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Semantics(
          label: fromUser ? 'Você' : 'Assistente',
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: EvoSpace.lg,
              vertical: EvoSpace.md,
            ),
            decoration: BoxDecoration(
              color: fromUser ? EvoColors.accent : EvoColors.bgSurface,
              borderRadius: BorderRadius.circular(EvoRadius.input),
              border: fromUser
                  ? null
                  : Border.all(color: EvoColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  message.content,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: fromUser
                        ? EvoColors.onAccent
                        : EvoColors.textPrimary,
                  ),
                ),
                if (tools != null) ...[
                  const SizedBox(height: EvoSpace.sm),
                  Text(
                    tools,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: EvoColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'O assistente está consultando seus registros',
    child: const Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: EvoSpace.md),
          ExcludeSemantics(child: Text('Consultando seus registros…')),
        ],
      ),
    ),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.error,
    required this.remainingToday,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final String? error;
  final int? remainingToday;
  final Future<void> Function([String?]) onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: EvoColors.bgBase,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          EvoSpace.xl,
          EvoSpace.sm,
          EvoSpace.xl,
          EvoSpace.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error case final message?)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: EvoSpace.sm),
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: EvoColors.danger,
                    ),
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !sending,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: _ChatPageState.maxChars,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Pergunte sobre seus treinos…',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: EvoSpace.sm),
                IconButton.filled(
                  tooltip: 'Enviar pergunta',
                  style: IconButton.styleFrom(
                    backgroundColor: EvoColors.accent,
                    foregroundColor: EvoColors.onAccent,
                    disabledBackgroundColor: EvoColors.bgElevated,
                    disabledForegroundColor: EvoColors.textSecondary,
                    minimumSize: const Size(52, 52),
                  ),
                  onPressed: sending ? null : () => onSend(),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
            if (remainingToday case final remaining?)
              Padding(
                padding: const EdgeInsets.only(top: EvoSpace.xs),
                child: Text(
                  switch (remaining) {
                    0 => 'Você usou todas as perguntas de hoje.',
                    1 => 'Resta 1 pergunta hoje.',
                    _ => 'Restam $remaining perguntas hoje.',
                  },
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: EvoColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sem o consentimento `ai_processing`, nada vai ao assistente: a pessoa autoriza
/// aqui mesmo (e pode desligar no perfil).
class _ConsentCard extends ConsumerStatefulWidget {
  const _ConsentCard();

  @override
  ConsumerState<_ConsentCard> createState() => _ConsentCardState();
}

class _ConsentCardState extends ConsumerState<_ConsentCard> {
  bool _saving = false;
  String? _error;

  Future<void> _grant() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(profileActionsProvider)
          .setConsent(ConsentKinds.aiProcessing, granted: true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: EvoColors.bgElevated,
      child: Padding(
        padding: const EdgeInsets.all(EvoSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Autorize as análises com IA',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: EvoSpace.sm),
            Text(
              'Para responder, o assistente consulta os registros ligados à '
              'pergunta (treinos, atividades, metas e perfil) e os envia ao '
              'provedor de IA do servidor. Seu nome e e-mail não são enviados. '
              'Dá para desligar no perfil a qualquer momento.',
              style: theme.textTheme.bodyMedium,
            ),
            if (_error case final message?) ...[
              const SizedBox(height: EvoSpace.sm),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: EvoColors.danger,
                ),
              ),
            ],
            const SizedBox(height: EvoSpace.lg),
            EvoButton(
              label: 'Autorizar e continuar',
              isLoading: _saving,
              onPressed: _grant,
            ),
          ],
        ),
      ),
    );
  }
}
