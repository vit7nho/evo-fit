import 'package:flutter/foundation.dart';

/// Tipos de plano da API.
abstract final class PlanKinds {
  static const walkHabit = 'walk_habit';
  static const run5k = 'run_5k';
  static const run10k = 'run_10k';
}

abstract final class PlanStatuses {
  static const active = 'active';
  static const completed = 'completed';
  static const ended = 'ended';
}

/// Um plano oferecido, já com os ajustes para a pessoa (docs/API.md).
@immutable
class PlanTemplate {
  const PlanTemplate({
    required this.kind,
    required this.title,
    required this.summary,
    required this.modality,
    required this.weeks,
    required this.sessionsPerWeek,
    this.prerequisite,
    this.adaptations = const [],
    this.note,
  });

  factory PlanTemplate.fromJson(Map<String, dynamic> json) => PlanTemplate(
    kind: json['kind'] as String,
    title: json['title'] as String,
    summary: json['summary'] as String,
    modality: json['modality'] as String,
    weeks: json['weeks'] as int,
    sessionsPerWeek: json['sessions_per_week'] as int,
    prerequisite: json['prerequisite'] as String?,
    adaptations: (json['adaptations'] as List<dynamic>).cast<String>(),
    note: json['note'] as String?,
  );

  final String kind;
  final String title;
  final String summary;
  final String modality;
  final int weeks;
  final int sessionsPerWeek;
  final String? prerequisite;
  final List<String> adaptations;

  /// Aviso quando o histórico sugere outro plano antes (não impede de começar).
  final String? note;

  bool get runs => modality == 'run';
}

@immutable
class PlanSession {
  const PlanSession({
    required this.id,
    required this.position,
    required this.week,
    required this.dayIndex,
    required this.scheduledDate,
    required this.totalS,
    required this.summary,
    this.completedActivityId,
  });

  factory PlanSession.fromJson(Map<String, dynamic> json) => PlanSession(
    id: json['id'] as String,
    position: json['position'] as int,
    week: json['week'] as int,
    dayIndex: json['day_index'] as int,
    scheduledDate: DateTime.parse(json['scheduled_date'] as String),
    totalS: json['total_s'] as int,
    summary: json['summary'] as String,
    completedActivityId: json['completed_activity_id'] as String?,
  );

  final String id;
  final int position;
  final int week;
  final int dayIndex;

  /// Sugestão de data: a próxima sessão é sempre a primeira não feita.
  final DateTime scheduledDate;

  /// Duração prevista, com aquecimento e volta à calma.
  final int totalS;

  /// "5 min caminhando · 8x (1 min correndo + 1:30 caminhando) · …"
  final String summary;
  final String? completedActivityId;

  bool get done => completedActivityId != null;
}

@immutable
class TrainingPlan {
  const TrainingPlan({
    required this.id,
    required this.kind,
    required this.title,
    required this.modality,
    required this.status,
    required this.startDate,
    required this.weekdays,
    required this.weeks,
    required this.currentWeek,
    required this.totalSessions,
    required this.completedSessions,
    this.nextSessionId,
    this.adaptations = const [],
    this.sessions = const [],
  });

  factory TrainingPlan.fromJson(Map<String, dynamic> json) => TrainingPlan(
    id: json['id'] as String,
    kind: json['kind'] as String,
    title: json['title'] as String,
    modality: json['modality'] as String,
    status: json['status'] as String,
    startDate: DateTime.parse(json['start_date'] as String),
    weekdays: (json['weekdays'] as List<dynamic>).cast<int>(),
    weeks: json['weeks'] as int,
    currentWeek: json['current_week'] as int,
    totalSessions: json['total_sessions'] as int,
    completedSessions: json['completed_sessions'] as int,
    nextSessionId: json['next_session_id'] as String?,
    adaptations: (json['adaptations'] as List<dynamic>).cast<String>(),
    sessions: (json['sessions'] as List<dynamic>? ?? const [])
        .map((s) => PlanSession.fromJson(s as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String kind;
  final String title;
  final String modality;
  final String status;
  final DateTime startDate;

  /// 0 = segunda … 6 = domingo.
  final List<int> weekdays;
  final int weeks;

  /// A semana da próxima sessão (vem também no resumo, que não traz as sessões).
  final int currentWeek;
  final int totalSessions;
  final int completedSessions;
  final String? nextSessionId;
  final List<String> adaptations;

  /// Vazio na lista (só o detalhe traz as sessões).
  final List<PlanSession> sessions;

  bool get active => status == PlanStatuses.active;

  PlanSession? get nextSession =>
      sessions.where((s) => s.id == nextSessionId).firstOrNull;
}

/// "seg", "ter"… na ordem da API (0 = segunda).
const weekdayShort = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
const weekdayLong = [
  'Segunda',
  'Terça',
  'Quarta',
  'Quinta',
  'Sexta',
  'Sábado',
  'Domingo',
];

/// Mesma regra da API: 3 dias diferentes; na corrida, sem dias seguidos (domingo e
/// segunda contam como seguidos). Nulo se estiver tudo certo.
String? checkPlanWeekdays(Set<int> days, {required bool runs}) {
  if (days.length != 3) return 'Escolha 3 dias.';
  if (runs && days.any((d) => days.contains((d + 1) % 7))) {
    return 'Na corrida, deixe um dia de descanso entre as sessões.';
  }
  return null;
}
