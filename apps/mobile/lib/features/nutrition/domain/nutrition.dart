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
  });

  factory DailyNutrition.fromJson(Map<String, dynamic> json) => DailyNutrition(
    date: DateTime.parse(json['date'] as String),
    totals: Nutrients.fromJson(json['totals'] as Map<String, dynamic>),
    meals: [
      for (final m in json['meals'] as List<dynamic>)
        Meal.fromJson(m as Map<String, dynamic>),
    ],
  );

  final DateTime date;
  final Nutrients totals;
  final List<Meal> meals;
}
