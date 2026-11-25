/// Nutrição (5.1, contrato em docs/API.md §Fase 5): alimentos por 100 g, refeições
/// com a cópia dos nutrientes e os totais do dia.
library;

const mealTypeLabels = {
  'breakfast': 'Café da manhã',
  'lunch': 'Almoço',
  'dinner': 'Jantar',
  'snack': 'Lanche',
  'other': 'Outra',
};

double _num(Object? value) => (value as num).toDouble();
double? _optional(Object? value) => (value as num?)?.toDouble();

class Nutrients {
  const Nutrients({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.fiberG,
  });

  factory Nutrients.fromJson(Map<String, dynamic> json) => Nutrients(
    kcal: _num(json['kcal']),
    proteinG: _num(json['protein_g']),
    carbsG: _num(json['carbs_g']),
    fatG: _num(json['fat_g']),
    fiberG: _optional(json['fiber_g']),
  );

  static const zero = Nutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0);

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// Nulo quando nada tem fibra registrada (não é zero).
  final double? fiberG;

  /// Nutrientes de [grams] de um alimento cujos valores são por 100 g (prévia no
  /// formulário; quem grava o valor final é a API).
  Nutrients scaled(double grams) {
    double r(double v) => (v * grams / 100 * 10).roundToDouble() / 10;
    return Nutrients(
      kcal: r(kcal),
      proteinG: r(proteinG),
      carbsG: r(carbsG),
      fatG: r(fatG),
      fiberG: fiberG == null ? null : r(fiberG!),
    );
  }

  Nutrients operator +(Nutrients other) => Nutrients(
    kcal: kcal + other.kcal,
    proteinG: proteinG + other.proteinG,
    carbsG: carbsG + other.carbsG,
    fatG: fatG + other.fatG,
    fiberG: fiberG == null && other.fiberG == null
        ? null
        : (fiberG ?? 0) + (other.fiberG ?? 0),
  );
}

/// "12,5" (uma casa, vírgula, sem ",0").
String formatGrams(double value) {
  final rounded = (value * 10).roundToDouble() / 10;
  final text = rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toStringAsFixed(1);
  return text.replaceAll('.', ',');
}

/// "P 42 g · C 42,2 g · G 3,3 g".
String describeMacros(Nutrients n) =>
    'P ${formatGrams(n.proteinG)} g · C ${formatGrams(n.carbsG)} g · '
    'G ${formatGrams(n.fatG)} g';

class Food {
  const Food({
    required this.id,
    required this.name,
    required this.source,
    required this.mine,
    required this.per100g,
    this.sourceRef,
    this.defaultPortionG,
  });

  factory Food.fromJson(Map<String, dynamic> json) => Food(
    id: json['id'] as String,
    name: json['name'] as String,
    source: json['source'] as String,
    sourceRef: json['source_ref'] as String?,
    mine: json['mine'] as bool,
    per100g: Nutrients.fromJson(json),
    defaultPortionG: json['default_portion_g'] as int?,
  );

  final String id;
  final String name;
  final String source;
  final String? sourceRef;
  final bool mine;
  final Nutrients per100g;
  final int? defaultPortionG;

  /// De onde vêm os valores (a TACO exige a citação da fonte).
  String get sourceLabel => switch (source) {
    'taco' => 'Fonte: TACO (NEPA/UNICAMP)',
    'user' => 'Criado por você',
    _ => 'Catálogo EvoFit',
  };
}

class MealItem {
  const MealItem({
    required this.foodId,
    required this.foodName,
    required this.quantityG,
    required this.nutrients,
  });

  factory MealItem.fromJson(Map<String, dynamic> json) => MealItem(
    foodId: json['food_id'] as String?,
    foodName: json['food_name'] as String,
    quantityG: _num(json['quantity_g']),
    nutrients: Nutrients.fromJson(json),
  );

  /// Nulo se o alimento próprio foi apagado depois (o item fica com a cópia).
  final String? foodId;
  final String foodName;
  final double quantityG;
  final Nutrients nutrients;
}

class Meal {
  const Meal({
    required this.id,
    required this.localTime,
    required this.mealType,
    required this.items,
    required this.totals,
    this.notes,
  });

  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
    id: json['id'] as String,
    // Horário no fuso do perfil, sem fuso: é o que a pessoa vê e edita, mesmo com o
    // aparelho em outro fuso.
    localTime: DateTime.parse(json['local_time'] as String),
    mealType: json['meal_type'] as String,
    notes: json['notes'] as String?,
    items: [
      for (final i in json['items'] as List<dynamic>)
        MealItem.fromJson(i as Map<String, dynamic>),
    ],
    totals: Nutrients.fromJson(json['totals'] as Map<String, dynamic>),
  );

  final String id;
  final DateTime localTime;
  final String mealType;
  final String? notes;
  final List<MealItem> items;
  final Nutrients totals;

  String get label => mealTypeLabels[mealType] ?? mealType;
}

class DailyNutrition {
  const DailyNutrition({
    required this.date,
    required this.totals,
    required this.meals,
    this.targets,
  });

  factory DailyNutrition.fromJson(Map<String, dynamic> json) => DailyNutrition(
    date: DateTime.parse(json['date'] as String),
    totals: Nutrients.fromJson(json['totals'] as Map<String, dynamic>),
    meals: [
      for (final m in json['meals'] as List<dynamic>)
        Meal.fromJson(m as Map<String, dynamic>),
    ],
    targets: switch (json['targets']) {
      final Map<String, dynamic> t => NutritionTargets.fromJson(t),
      _ => null,
    },
  );

  final DateTime date;
  final Nutrients totals;
  final List<Meal> meals;

  /// A meta que vale neste dia (5.2); nula sem metas.
  final NutritionTargets? targets;
}

// --- metas (5.2, ADR-059) ---

/// Calorias de [proteinG], [carbsG] e [fatG] (4/4/9 kcal por grama); nulo sem nenhum.
int? macrosKcal(int? proteinG, int? carbsG, int? fatG) {
  if (proteinG == null && carbsG == null && fatG == null) return null;
  return (proteinG ?? 0) * 4 + (carbsG ?? 0) * 4 + (fatG ?? 0) * 9;
}

/// "2.000" (milhar com ponto).
String formatInt(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => '.',
);

class NutritionTargets {
  const NutritionTargets({
    required this.validFrom,
    this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
  });

  factory NutritionTargets.fromJson(Map<String, dynamic> json) =>
      NutritionTargets(
        validFrom: DateTime.parse(json['valid_from'] as String),
        kcal: json['kcal'] as int?,
        proteinG: json['protein_g'] as int?,
        carbsG: json['carbs_g'] as int?,
        fatG: json['fat_g'] as int?,
      );

  final DateTime validFrom;
  final int? kcal;
  final int? proteinG;
  final int? carbsG;
  final int? fatG;

  /// "2.000 kcal · P 150 g · C 200 g · G 67 g" (só o que tem meta).
  String get description => [
    if (kcal case final k?) '${formatInt(k)} kcal',
    if (proteinG case final p?) 'P $p g',
    if (carbsG case final c?) 'C $c g',
    if (fatG case final f?) 'G $f g',
  ].join(' · ');
}

class TargetRange {
  const TargetRange(this.min, this.max);

  factory TargetRange.fromJson(Map<String, dynamic> json) =>
      TargetRange(json['min'] as int, json['max'] as int);

  final int min;
  final int max;

  bool contains(int value) => value >= min && value <= max;
}

/// O que a pessoa pode escolher (os limites de segurança vêm da API).
class TargetLimits {
  const TargetLimits({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.kcalAllowed,
    required this.macrosTolerancePct,
  });

  factory TargetLimits.fromJson(Map<String, dynamic> json) {
    TargetRange range(String key) =>
        TargetRange.fromJson(json[key] as Map<String, dynamic>);
    return TargetLimits(
      kcal: range('kcal'),
      proteinG: range('protein_g'),
      carbsG: range('carbs_g'),
      fatG: range('fat_g'),
      kcalAllowed: json['kcal_allowed'] as bool,
      macrosTolerancePct: json['macros_tolerance_pct'] as int,
    );
  }

  final TargetRange kcal;
  final TargetRange proteinG;
  final TargetRange carbsG;
  final TargetRange fatG;

  /// Falso para menores de 18 anos: meta de calorias só com acompanhamento.
  final bool kcalAllowed;
  final int macrosTolerancePct;
}

class TargetsInfo {
  const TargetsInfo({
    required this.current,
    required this.history,
    required this.limits,
  });

  factory TargetsInfo.fromJson(Map<String, dynamic> json) => TargetsInfo(
    current: switch (json['current']) {
      final Map<String, dynamic> t => NutritionTargets.fromJson(t),
      _ => null,
    },
    history: [
      for (final t in json['history'] as List<dynamic>)
        NutritionTargets.fromJson(t as Map<String, dynamic>),
    ],
    limits: TargetLimits.fromJson(json['limits'] as Map<String, dynamic>),
  );

  final NutritionTargets? current;
  final List<NutritionTargets> history;
  final TargetLimits limits;
}

/// Quanto do dia já foi, em relação à meta (0 a 1, para a barra).
double progressOf(double value, int target) =>
    target <= 0 ? 0 : (value / target).clamp(0, 1).toDouble();
