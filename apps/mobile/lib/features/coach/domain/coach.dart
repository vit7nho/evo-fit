/// Conversas com o assistente de IA (4.5, contrato em docs/API.md §Fase 4).
library;

/// Do que a conversa trata: tudo (global) ou um registro/recorte específico.
enum CoachScope {
  global('global', 'Conversa geral'),
  session('session', 'Sobre um treino'),
  exercise('exercise', 'Sobre um exercício'),
  muscle('muscle', 'Sobre um músculo'),
  activity('activity', 'Sobre uma atividade'),
  period('period', 'Sobre um período');

  const CoachScope(this.code, this.label);

  final String code;
  final String label;

  static CoachScope of(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => global);
}

/// Nome que a pessoa reconhece para cada ferramenta consultada (sem jargão).
const toolLabels = {
  'get_profile_summary': 'perfil',
  'get_goals': 'metas',
  'get_workout_history': 'treinos',
  'get_current_session': 'treino em andamento',
  'get_session_detail': 'detalhe do treino',
  'get_exercise_history': 'histórico do exercício',
  'search_exercises': 'biblioteca de exercícios',
  'get_muscle_stimulus': 'Meu Corpo',
  'compare_periods': 'comparativos',
  'get_activities': 'atividades',
  'get_endurance_progress': 'evolução de resistência',
  'get_templates': 'fichas de treino',
  'prepare_change_proposal': 'proposta de alteração',
};

/// "Consultou: treinos e Meu Corpo" (nulo se nada foi consultado).
String? describeTools(List<String> tools) {
  final names = {for (final t in tools) toolLabels[t] ?? t}.toList();
  if (names.isEmpty) return null;
  final joined = names.length == 1
      ? names.first
      : '${names.sublist(0, names.length - 1).join(', ')} e ${names.last}';
  return 'Consultou: $joined';
}

class Conversation {
  const Conversation({
    required this.id,
    required this.scope,
    required this.scopeRef,
    required this.title,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    scope: CoachScope.of(json['scope'] as String),
    scopeRef: (json['scope_ref'] as Map?)?.cast<String, dynamic>(),
    title: json['title'] as String,
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final String id;
  final CoachScope scope;
  final Map<String, dynamic>? scopeRef;
  final String title;
  final DateTime updatedAt;
}

enum ProposalStatus {
  pending('Aguardando sua resposta'),
  accepted('Aplicada'),
  rejected('Recusada'),
  expired('Expirou'),
  failed('Não aplicada');

  const ProposalStatus(this.label);

  final String label;

  static ProposalStatus of(String code) =>
      values.firstWhere((s) => s.name == code, orElse: () => failed);
}

/// Alteração sugerida pela IA (4.6): nada muda até a pessoa confirmar.
class Proposal {
  const Proposal({
    required this.id,
    required this.summary,
    required this.details,
    required this.rationale,
    required this.status,
    this.result,
    this.templateId,
    this.goalId,
  });

  factory Proposal.fromJson(Map<String, dynamic> json) => Proposal(
    id: json['id'] as String,
    summary: json['summary'] as String,
    details: [for (final d in json['details'] as List<dynamic>) d as String],
    rationale: json['rationale'] as String,
    status: ProposalStatus.of(json['status'] as String),
    result: json['result'] as String?,
    templateId: json['template_id'] as String?,
    goalId: json['goal_id'] as String?,
  );

  final String id;
  final String summary;
  final List<String> details;
  final String rationale;
  final ProposalStatus status;

  /// Por que não foi aplicada (só quando falhou).
  final String? result;
  final String? templateId;
  final String? goalId;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.fromUser,
    required this.content,
    this.toolsUsed = const [],
    this.proposals = const [],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    fromUser: json['role'] == 'user',
    content: json['content'] as String,
    toolsUsed: [
      for (final t in json['tools_used'] as List<dynamic>? ?? const [])
        t as String,
    ],
    proposals: [
      for (final p in json['proposals'] as List<dynamic>? ?? const [])
        Proposal.fromJson(p as Map<String, dynamic>),
    ],
  );

  final String id;
  final bool fromUser;
  final String content;
  final List<String> toolsUsed;
  final List<Proposal> proposals;

  ChatMessage withProposal(Proposal updated) => ChatMessage(
    id: id,
    fromUser: fromUser,
    content: content,
    toolsUsed: toolsUsed,
    proposals: [for (final p in proposals) p.id == updated.id ? updated : p],
  );
}

/// Resposta de uma pergunta: as duas mensagens gravadas e o estado da cota.
class CoachReply {
  const CoachReply({
    required this.question,
    required this.answer,
    required this.simulated,
    required this.remainingToday,
  });

  factory CoachReply.fromJson(Map<String, dynamic> json) => CoachReply(
    question: ChatMessage.fromJson(json['question'] as Map<String, dynamic>),
    answer: ChatMessage.fromJson(json['answer'] as Map<String, dynamic>),
    simulated: json['simulated'] as bool,
    remainingToday: json['remaining_today'] as int,
  );

  final ChatMessage question;
  final ChatMessage answer;
  final bool simulated;
  final int remainingToday;
}

/// Conversa aberta na tela: as mensagens e o que a última resposta informou.
class ChatState {
  const ChatState({
    required this.conversation,
    required this.messages,
    this.pending,
    this.simulated = false,
    this.remainingToday,
  });

  final Conversation conversation;
  final List<ChatMessage> messages;

  /// Pergunta enviada e ainda sem resposta (mostrada enquanto a IA pensa).
  final String? pending;
  final bool simulated;
  final int? remainingToday;

  bool get sending => pending != null;

  ChatState copyWith({
    List<ChatMessage>? messages,
    String? Function()? pending,
    bool? simulated,
    int? remainingToday,
  }) => ChatState(
    conversation: conversation,
    messages: messages ?? this.messages,
    pending: pending == null ? this.pending : pending(),
    simulated: simulated ?? this.simulated,
    remainingToday: remainingToday ?? this.remainingToday,
  );
}

/// Perguntas de partida, conforme o foco da conversa.
List<String> suggestionsFor(CoachScope scope) => switch (scope) {
  CoachScope.muscle => const [
    'Como está o estímulo deste músculo?',
    'Quais exercícios mais trabalharam este músculo?',
    'Treinei mais ou menos que no período anterior?',
  ],
  CoachScope.session => const [
    'Como foi este treino?',
    'Bati algum recorde neste treino?',
    'O que mudou em relação ao treino anterior?',
  ],
  _ => const [
    'O que fiz na minha última sessão?',
    'Como foi minha semana de treinos?',
    'Quais músculos treinei menos nos últimos 30 dias?',
  ],
};
