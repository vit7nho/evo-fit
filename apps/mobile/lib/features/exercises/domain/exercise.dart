import 'package:flutter/foundation.dart';

import '../../profile/domain/profile.dart';

/// Papel de um músculo no exercício (códigos da API).
abstract final class MuscleRole {
  static const primary = 'primary';
  static const secondary = 'secondary';
}

@immutable
class ExerciseMuscle {
  const ExerciseMuscle({
    required this.id,
    required this.name,
    required this.role,
  });

  factory ExerciseMuscle.fromJson(Map<String, dynamic> json) => ExerciseMuscle(
    id: json['id'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
  );

  final String id;
  final String name;
  final String role;

  bool get isPrimary => role == MuscleRole.primary;
}

/// Exercício como devolvido pela API: do catálogo do projeto ou criado pelo usuário.
@immutable
class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.mechanics,
    required this.equipment,
    required this.loadType,
    required this.muscles,
    this.instructions,
    this.unilateral = false,
    this.isCustom = false,
    this.isActive = true,
    this.images = const [],
  });

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id'] as String,
    name: json['name'] as String,
    instructions: json['instructions'] as String?,
    mechanics: json['mechanics'] as String,
    equipment: json['equipment'] as String,
    loadType: json['load_type'] as String,
    unilateral: json['unilateral'] as bool? ?? false,
    isCustom: json['is_custom'] as bool? ?? false,
    isActive: json['is_active'] as bool? ?? true,
    images: (json['images'] as List<dynamic>? ?? const []).cast<String>(),
    muscles: (json['muscles'] as List<dynamic>)
        .map((m) => ExerciseMuscle.fromJson(m as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String name;
  final String? instructions;
  final String mechanics;
  final String equipment;
  final String loadType;
  final bool unilateral;

  /// Criado pelo usuário (editável); os do catálogo são só leitura.
  final bool isCustom;
  final bool isActive;
  final List<ExerciseMuscle> muscles;

  /// Fotos do catálogo (posição inicial e final), caminhos relativos à API.
  final List<String> images;

  List<ExerciseMuscle> get primaryMuscles =>
      muscles.where((m) => m.isPrimary).toList();
  List<ExerciseMuscle> get secondaryMuscles =>
      muscles.where((m) => !m.isPrimary).toList();
}

@immutable
class MuscleGroup {
  const MuscleGroup({required this.id, required this.name});

  factory MuscleGroup.fromJson(Map<String, dynamic> json) =>
      MuscleGroup(id: json['id'] as String, name: json['name'] as String);

  final String id;
  final String name;
}

/// Vocabulários da biblioteca (GET /exercise-options), na ordem de exibição.
@immutable
class ExerciseOptions {
  const ExerciseOptions({
    required this.muscleGroups,
    required this.equipment,
    required this.mechanics,
    required this.loadTypes,
  });

  factory ExerciseOptions.fromJson(Map<String, dynamic> json) {
    List<Option> options(String key) => (json[key] as List<dynamic>)
        .map((o) => Option.fromJson(o as Map<String, dynamic>))
        .toList();
    return ExerciseOptions(
      muscleGroups: (json['muscle_groups'] as List<dynamic>)
          .map((m) => MuscleGroup.fromJson(m as Map<String, dynamic>))
          .toList(),
      equipment: options('equipment'),
      mechanics: options('mechanics'),
      loadTypes: options('load_types'),
    );
  }

  final List<MuscleGroup> muscleGroups;
  final List<Option> equipment;
  final List<Option> mechanics;
  final List<Option> loadTypes;
}

// --- busca e filtros (no aparelho: a biblioteca inteira cabe em memória) ---

const _accents = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

/// Texto sem acentos e em minúsculas, igual à chave de busca da API.
String searchKey(String text) {
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    buffer.write(_accents[char] ?? char);
  }
  return buffer
      .toString()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .join(' ');
}

/// Equipamentos da biblioteca que a pessoa tem, pelo que marcou no perfil.
///
/// Nulo quando não há o que restringir: "academia completa" cobre tudo, e sem
/// equipamentos no perfil não dá para saber. O peso do corpo vale sempre.
Set<String>? availableEquipment(List<String> profileEquipment) {
  if (profileEquipment.isEmpty || profileEquipment.contains('gym')) return null;
  const sameCode = {
    'barbell',
    'dumbbells',
    'kettlebell',
    'bands',
    'pull_up_bar',
    'bodyweight',
  };
  return {...profileEquipment.where(sameCode.contains), 'bodyweight'};
}

/// Aplica a busca (todas as palavras no nome, sem acentos), o músculo e os
/// equipamentos permitidos. Mantém a ordem recebida.
List<Exercise> filterExercises(
  List<Exercise> exercises, {
  String query = '',
  String? muscle,
  Set<String>? equipment,
  bool mineOnly = false,
}) {
  final words = searchKey(query).split(' ').where((w) => w.isNotEmpty);
  return [
    for (final exercise in exercises)
      if ((!mineOnly || exercise.isCustom) &&
          (muscle == null || exercise.muscles.any((m) => m.id == muscle)) &&
          (equipment == null || equipment.contains(exercise.equipment)) &&
          words.every(searchKey(exercise.name).contains))
        exercise,
  ];
}
