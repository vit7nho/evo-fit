import 'package:flutter/foundation.dart';

import '../../profile/domain/profile.dart';

/// Status de uma meta (códigos da API).
abstract final class GoalStatus {
  static const active = 'active';
  static const achieved = 'achieved';
  static const abandoned = 'abandoned';
}

/// Tipos de campo do alvo, como definidos em GET /goal-options.
abstract final class TargetFieldType {
  static const text = 'text';
  static const integer = 'int';
  static const number = 'number';
  static const choice = 'choice';
  static const duration = 'duration';
}

/// Um campo do alvo de um tipo de meta. Em `text`, [min]/[max] são o tamanho do
/// texto; em `duration`, segundos.
@immutable
class TargetField {
  const TargetField({
    required this.key,
    required this.label,
    required this.type,
    this.required = true,
    this.min,
    this.max,
    this.step,
    this.unit,
    this.options,
  });

  factory TargetField.fromJson(Map<String, dynamic> json) => TargetField(
    key: json['key'] as String,
    label: json['label'] as String,
    type: json['type'] as String,
    required: json['required'] as bool? ?? true,
    min: (json['min'] as num?)?.toDouble(),
    max: (json['max'] as num?)?.toDouble(),
    step: (json['step'] as num?)?.toDouble(),
    unit: json['unit'] as String?,
    options: (json['options'] as List<dynamic>?)
        ?.map((o) => Option.fromJson(o as Map<String, dynamic>))
        .toList(),
  );

  final String key;
  final String label;
  final String type;
  final bool required;
  final double? min;
  final double? max;
  final double? step;
  final String? unit;
  final List<Option>? options;
}

@immutable
class GoalKind {
  const GoalKind({
    required this.code,
    required this.label,
    required this.description,
    required this.fields,
    this.healthData = false,
  });

  factory GoalKind.fromJson(Map<String, dynamic> json) => GoalKind(
    code: json['code'] as String,
    label: json['label'] as String,
    description: json['description'] as String,
    healthData: json['health_data'] as bool? ?? false,
    fields: (json['fields'] as List<dynamic>)
        .map((f) => TargetField.fromJson(f as Map<String, dynamic>))
        .toList(),
  );

  final String code;
  final String label;
  final String description;

  /// Exige o consentimento `health_data` (metas de peso).
  final bool healthData;
  final List<TargetField> fields;
}

/// Tipos de meta e rótulos (GET /goal-options). O formulário de cada tipo é
/// montado a partir daqui: um tipo novo na API aparece sem atualizar o app.
@immutable
class GoalOptions {
  const GoalOptions({
    required this.kinds,
    required this.statuses,
    required this.priorities,
  });

  factory GoalOptions.fromJson(Map<String, dynamic> json) => GoalOptions(
    kinds: (json['kinds'] as List<dynamic>)
        .map((k) => GoalKind.fromJson(k as Map<String, dynamic>))
        .toList(),
    statuses: (json['statuses'] as List<dynamic>)
        .map((s) => Option.fromJson(s as Map<String, dynamic>))
        .toList(),
    priorities: [
      for (final p in json['priorities'] as List<dynamic>)
        ((p as Map<String, dynamic>)['value'] as int, p['label'] as String),
    ],
  );

  final List<GoalKind> kinds;
  final List<Option> statuses;
  final List<(int, String)> priorities;

  GoalKind? kind(String code) {
    for (final kind in kinds) {
      if (kind.code == code) return kind;
    }
    return null;
  }

  String statusLabel(String code) => ProfileOptions.labelOf(statuses, code);

  String priorityLabel(int value) => priorities
      .firstWhere((p) => p.$1 == value, orElse: () => (value, '$value'))
      .$2;
}

/// Meta como devolvida pela API.
@immutable
class Goal {
  const Goal({
    required this.id,
    required this.kind,
    required this.title,
    required this.target,
    required this.summary,
    required this.startDate,
    required this.status,
    required this.priority,
    this.targetDate,
    this.closedAt,
  });

  factory Goal.fromJson(Map<String, dynamic> json) {
    final targetDate = json['target_date'] as String?;
    final closedAt = json['closed_at'] as String?;
    return Goal(
      id: json['id'] as String,
      kind: json['kind'] as String,
      title: json['title'] as String,
      target: Map<String, Object?>.from(json['target'] as Map),
      summary: json['summary'] as String? ?? '',
      startDate: DateTime.parse(json['start_date'] as String),
      targetDate: targetDate == null ? null : DateTime.parse(targetDate),
      status: json['status'] as String,
      priority: json['priority'] as int,
      closedAt: closedAt == null ? null : DateTime.parse(closedAt),
    );
  }

  final String id;
  final String kind;
  final String title;
  final Map<String, Object?> target;

  /// Alvo em texto, montado pela API (ex.: "5 km em 25:30").
  final String summary;
  final DateTime startDate;
  final DateTime? targetDate;
  final String status;
  final int priority;
  final DateTime? closedAt;

  bool get isActive => status == GoalStatus.active;

  /// Ativa com o prazo já passado (comparando só a data).
  bool isOverdue(DateTime today) {
    final deadline = targetDate;
    if (!isActive || deadline == null) return false;
    return deadline.isBefore(dateOnly(today));
  }
}

/// Data no formato da API (AAAA-MM-DD), sem fuso.
String apiDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// A data sem a hora.
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
