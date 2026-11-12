import 'package:flutter/foundation.dart';

/// Painel do Início (GET /dashboard, etapa 3.8). Os números e a ordem do foco vêm
/// da API; o app só mostra.
@immutable
class Dashboard {
  const Dashboard({
    required this.today,
    required this.week,
    required this.focus,
    required this.goals,
    required this.activeGoals,
    this.objective,
    this.objectiveLabel,
    this.lastRecord,
  });

  factory Dashboard.fromJson(Map<String, dynamic> json) => Dashboard(
    objective: json['objective'] as String?,
    objectiveLabel: json['objective_label'] as String?,
    today: DateTime.parse(json['today'] as String),
    week: DashboardWeek.fromJson(json['week'] as Map<String, dynamic>),
    focus: [
      for (final f in json['focus'] as List<dynamic>)
        FocusCard.fromJson(f as Map<String, dynamic>),
    ],
    goals: [
      for (final g in json['goals'] as List<dynamic>)
        GoalCard.fromJson(g as Map<String, dynamic>),
    ],
    activeGoals: json['active_goals'] as int,
    lastRecord: json['last_record'] == null
        ? null
        : LastRecord.fromJson(json['last_record'] as Map<String, dynamic>),
  );

  final String? objective;
  final String? objectiveLabel;
  final DateTime today;
  final DashboardWeek week;
  final List<FocusCard> focus;
  final List<GoalCard> goals;
  final int activeGoals;
  final LastRecord? lastRecord;
}

/// A semana em curso (segunda até hoje) e a anterior.
@immutable
class DashboardWeek {
  const DashboardWeek({
    required this.sessions,
    required this.activeDays,
    required this.durationS,
    required this.previousSessions,
    required this.previousActiveDays,
    required this.streakWeeks,
    this.weeklyTarget,
  });

  factory DashboardWeek.fromJson(Map<String, dynamic> json) => DashboardWeek(
    sessions: json['sessions'] as int,
    activeDays: json['active_days'] as int,
    durationS: json['duration_s'] as int,
    weeklyTarget: json['weekly_target'] as int?,
    previousSessions: json['previous_sessions'] as int,
    previousActiveDays: json['previous_active_days'] as int,
    streakWeeks: json['streak_weeks'] as int,
  );

  final int sessions;
  final int activeDays;
  final int durationS;
  final int? weeklyTarget;
  final int previousSessions;
  final int previousActiveDays;
  final int streakWeeks;
}

/// Um cartão do foco. Só o campo do tipo vem preenchido.
sealed class FocusCard {
  const FocusCard();

  factory FocusCard.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> part(String key) => json[key] as Map<String, dynamic>;
    return switch (json['kind']) {
      'strength' => StrengthFocus.fromJson(part('strength')),
      'body' => BodyFocus.fromJson(part('body')),
      'endurance' => EnduranceFocus.fromJson(part('endurance')),
      'plan' => PlanFocus.fromJson(part('plan')),
      final kind => throw FormatException('Cartão desconhecido: $kind'),
    };
  }
}

/// Musculação: últimos 7 dias contra os 7 anteriores.
class StrengthFocus extends FocusCard {
  const StrengthFocus({
    required this.sessions,
    required this.sets,
    required this.volumeKg,
    required this.previousSets,
    required this.previousVolumeKg,
  });

  factory StrengthFocus.fromJson(Map<String, dynamic> json) => StrengthFocus(
    sessions: json['sessions'] as int,
    sets: json['sets'] as int,
    volumeKg: (json['volume_kg'] as num).toDouble(),
    previousSets: json['previous_sets'] as int,
    previousVolumeKg: (json['previous_volume_kg'] as num).toDouble(),
  );

  final int sessions;
  final int sets;
  final double volumeKg;
  final int previousSets;
  final double previousVolumeKg;
}

/// Meu Corpo nos últimos 30 dias: os músculos de menor estímulo.
class BodyFocus extends FocusCard {
  const BodyFocus({
    required this.periodDays,
    required this.least,
    required this.untrained,
  });

  factory BodyFocus.fromJson(Map<String, dynamic> json) => BodyFocus(
    periodDays: json['period_days'] as int,
    least: [
      for (final m in json['least'] as List<dynamic>)
        (
          name: (m as Map<String, dynamic>)['name'] as String,
          perWeek: (m['weighted_sets_per_week'] as num).toDouble(),
        ),
    ],
    untrained: json['untrained'] as int,
  );

  final int periodDays;
  final List<({String name, double perWeek})> least;

  /// Quantos músculos ficaram sem nenhuma série.
  final int untrained;
}

/// Corrida, caminhada, ciclismo ou natação: últimos 7 dias.
class EnduranceFocus extends FocusCard {
  const EnduranceFocus({
    required this.modality,
    required this.sessions,
    required this.durationS,
    required this.distanceM,
    required this.previousDistanceM,
    this.paceSPerKm,
    this.speedKmh,
    this.paceSPer100m,
  });

  factory EnduranceFocus.fromJson(Map<String, dynamic> json) => EnduranceFocus(
    modality: json['modality'] as String,
    sessions: json['sessions'] as int,
    durationS: json['duration_s'] as int,
    distanceM: json['distance_m'] as int,
    previousDistanceM: json['previous_distance_m'] as int,
    paceSPerKm: json['pace_s_per_km'] as int?,
    speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
    paceSPer100m: json['pace_s_per_100m'] as int?,
  );

  final String modality;
  final int sessions;
  final int durationS;
  final int distanceM;
  final int previousDistanceM;
  final int? paceSPerKm;
  final double? speedKmh;
  final int? paceSPer100m;
}

/// O plano ativo e a próxima sessão dele.
class PlanFocus extends FocusCard {
  const PlanFocus({
    required this.id,
    required this.title,
    required this.currentWeek,
    required this.weeks,
    required this.completedSessions,
    required this.totalSessions,
    this.nextSession,
  });

  factory PlanFocus.fromJson(Map<String, dynamic> json) {
    final next = json['next_session'] as Map<String, dynamic>?;
    return PlanFocus(
      id: json['id'] as String,
      title: json['title'] as String,
      currentWeek: json['current_week'] as int,
      weeks: json['weeks'] as int,
      completedSessions: json['completed_sessions'] as int,
      totalSessions: json['total_sessions'] as int,
      nextSession: next == null
          ? null
          : (
              date: DateTime.parse(next['scheduled_date'] as String),
              summary: next['summary'] as String,
            ),
    );
  }

  final String id;
  final String title;
  final int currentWeek;
  final int weeks;
  final int completedSessions;
  final int totalSessions;
  final ({DateTime date, String summary})? nextSession;
}

/// Progresso medido pelos registros. [current] nulo = ainda sem registro que meça.
@immutable
class GoalProgress {
  const GoalProgress({
    required this.target,
    required this.unit,
    required this.achieved,
    required this.lowerIsBetter,
    required this.basis,
    this.current,
    this.ratio,
  });

  factory GoalProgress.fromJson(Map<String, dynamic> json) => GoalProgress(
    current: (json['current'] as num?)?.toDouble(),
    target: (json['target'] as num).toDouble(),
    unit: json['unit'] as String,
    ratio: (json['ratio'] as num?)?.toDouble(),
    achieved: json['achieved'] as bool,
    lowerIsBetter: json['lower_is_better'] as bool,
    basis: json['basis'] as String,
  );

  final double? current;
  final double target;

  /// kg | km | s | sets_per_week | sessions
  final String unit;
  final double? ratio;
  final bool achieved;
  final bool lowerIsBetter;
  final String basis;
}

@immutable
class GoalCard {
  const GoalCard({
    required this.id,
    required this.kind,
    required this.title,
    required this.summary,
    required this.priority,
    this.targetDate,
    this.progress,
  });

  factory GoalCard.fromJson(Map<String, dynamic> json) => GoalCard(
    id: json['id'] as String,
    kind: json['kind'] as String,
    title: json['title'] as String,
    summary: json['summary'] as String,
    priority: json['priority'] as int,
    targetDate: json['target_date'] == null
        ? null
        : DateTime.parse(json['target_date'] as String),
    progress: json['progress'] == null
        ? null
        : GoalProgress.fromJson(json['progress'] as Map<String, dynamic>),
  );

  final String id;
  final String kind;
  final String title;
  final String summary;
  final int priority;
  final DateTime? targetDate;

  /// Nulo nos tipos que os registros não medem (peso, hábito, livre).
  final GoalProgress? progress;
}

@immutable
class LastRecord {
  const LastRecord({
    required this.modality,
    required this.day,
    required this.durationS,
    this.title,
    this.distanceM,
    this.sets,
    this.volumeKg,
  });

  factory LastRecord.fromJson(Map<String, dynamic> json) => LastRecord(
    modality: json['modality'] as String,
    title: json['title'] as String?,
    day: DateTime.parse(json['day'] as String),
    durationS: json['duration_s'] as int,
    distanceM: json['distance_m'] as int?,
    sets: json['sets'] as int?,
    volumeKg: (json['volume_kg'] as num?)?.toDouble(),
  );

  final String modality;
  final String? title;
  final DateTime day;
  final int durationS;
  final int? distanceM;
  final int? sets;
  final double? volumeKg;
}
