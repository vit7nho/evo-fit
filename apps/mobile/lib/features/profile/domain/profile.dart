import 'package:flutter/foundation.dart';

/// Disponibilidade semanal declarada pelo usuário.
@immutable
class WeeklyAvailability {
  const WeeklyAvailability({
    required this.daysPerWeek,
    required this.minutesPerSession,
  });

  factory WeeklyAvailability.fromJson(Map<String, dynamic> json) =>
      WeeklyAvailability(
        daysPerWeek: json['days_per_week'] as int,
        minutesPerSession: json['minutes_per_session'] as int,
      );

  final int daysPerWeek;
  final int minutesPerSession;

  Map<String, Object> toJson() => {
    'days_per_week': daysPerWeek,
    'minutes_per_session': minutesPerSession,
  };

  @override
  bool operator ==(Object other) =>
      other is WeeklyAvailability &&
      other.daysPerWeek == daysPerWeek &&
      other.minutesPerSession == minutesPerSession;

  @override
  int get hashCode => Object.hash(daysPerWeek, minutesPerSession);
}

/// Perfil como devolvido por GET /me (campo `profile`).
@immutable
class UserProfile {
  const UserProfile({
    required this.displayName,
    this.birthYear,
    this.sexForCalculations,
    this.timezone = 'America/Sao_Paulo',
    this.unitSystem = 'metric',
    this.experienceLevel,
    this.weeklyAvailability,
    this.primaryObjective,
    this.secondaryObjectives = const [],
    this.preferredModalities = const [],
    this.equipment = const [],
    this.limitationTags = const [],
    this.limitationsNote,
    this.onboardingCompletedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    List<String> codes(String key) =>
        (json[key] as List<dynamic>? ?? const []).cast<String>();
    final availability = json['weekly_availability'] as Map<String, dynamic>?;
    final completed = json['onboarding_completed_at'] as String?;
    return UserProfile(
      displayName: json['display_name'] as String? ?? '',
      birthYear: json['birth_year'] as int?,
      sexForCalculations: json['sex_for_calculations'] as String?,
      timezone: json['timezone'] as String? ?? 'America/Sao_Paulo',
      unitSystem: json['unit_system'] as String? ?? 'metric',
      experienceLevel: json['experience_level'] as String?,
      weeklyAvailability: availability == null
          ? null
          : WeeklyAvailability.fromJson(availability),
      primaryObjective: json['primary_objective'] as String?,
      secondaryObjectives: codes('secondary_objectives'),
      preferredModalities: codes('preferred_modalities'),
      equipment: codes('equipment'),
      limitationTags: codes('limitation_tags'),
      limitationsNote: json['limitations_note'] as String?,
      onboardingCompletedAt: completed == null
          ? null
          : DateTime.parse(completed),
    );
  }

  final String displayName;
  final int? birthYear;
  final String? sexForCalculations;
  final String timezone;
  final String unitSystem;
  final String? experienceLevel;
  final WeeklyAvailability? weeklyAvailability;
  final String? primaryObjective;
  final List<String> secondaryObjectives;
  final List<String> preferredModalities;
  final List<String> equipment;
  final List<String> limitationTags;
  final String? limitationsNote;
  final DateTime? onboardingCompletedAt;

  bool get onboardingCompleted => onboardingCompletedAt != null;
}

/// Uma opção de vocabulário (código estável + rótulo em PT-BR) vinda da API.
@immutable
class Option {
  const Option(this.code, this.label);

  factory Option.fromJson(Map<String, dynamic> json) =>
      Option(json['code'] as String, json['label'] as String);

  final String code;
  final String label;
}

/// Opções válidas dos campos do perfil (GET /profile-options), na ordem de exibição.
@immutable
class ProfileOptions {
  const ProfileOptions({
    required this.objectives,
    required this.modalities,
    required this.equipment,
    required this.limitationTags,
    required this.experienceLevels,
    required this.unitSystems,
    required this.sexForCalculations,
  });

  factory ProfileOptions.fromJson(Map<String, dynamic> json) {
    List<Option> list(String key) => (json[key] as List<dynamic>)
        .map((e) => Option.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return ProfileOptions(
      objectives: list('objectives'),
      modalities: list('modalities'),
      equipment: list('equipment'),
      limitationTags: list('limitation_tags'),
      experienceLevels: list('experience_levels'),
      unitSystems: list('unit_systems'),
      sexForCalculations: list('sex_for_calculations'),
    );
  }

  final List<Option> objectives;
  final List<Option> modalities;
  final List<Option> equipment;
  final List<Option> limitationTags;
  final List<Option> experienceLevels;
  final List<Option> unitSystems;
  final List<Option> sexForCalculations;

  /// Rótulo de um código; o próprio código se a opção não existir mais.
  static String labelOf(List<Option> options, String? code) {
    if (code == null) return '';
    for (final option in options) {
      if (option.code == code) return option.label;
    }
    return code;
  }
}

/// Consentimentos que o usuário pode conceder e revogar pelo app.
abstract final class ConsentKinds {
  static const healthData = 'health_data';
  static const aiProcessing = 'ai_processing';
}
