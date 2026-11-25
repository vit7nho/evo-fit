import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../analytics/domain/analytics.dart' show apiDate;
import '../domain/nutrition.dart';

/// Alimentos, refeições e totais do dia (docs/API.md §Fase 5).
class NutritionApi {
  const NutritionApi(this._dio);

  final Dio _dio;

  Future<List<Food>> foods({String? query}) => guardApiCall(() async {
    final response = await _dio.get<List<dynamic>>(
      '/foods',
      queryParameters: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    return response.data!
        .map((f) => Food.fromJson(f as Map<String, dynamic>))
        .toList();
  });

  Future<Food> createFood(Map<String, Object?> body) => guardApiCall(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/foods',
      data: body,
    );
    return Food.fromJson(response.data!);
  });

  /// Sem [day]: hoje no fuso do perfil (o servidor decide).
  Future<DailyNutrition> daily(DateTime? day) => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/nutrition/daily',
      queryParameters: {if (day != null) 'date': apiDate(day)},
    );
    return DailyNutrition.fromJson(response.data!);
  });

  Future<Meal> saveMeal({
    String? id,
    required DateTime eatenAt,
    required String mealType,
    required List<(String foodId, double grams)> items,
    String? notes,
  }) => guardApiCall(() async {
    final body = {
      // Sem fuso: a API usa o do perfil, o mesmo que separa os dias.
      'eaten_at': localDateTime(eatenAt),
      'meal_type': mealType,
      'notes': ?notes,
      'items': [
        for (final (foodId, grams) in items)
          {'food_id': foodId, 'quantity_g': grams},
      ],
    };
    final response = id == null
        ? await _dio.post<Map<String, dynamic>>('/meals', data: body)
        : await _dio.put<Map<String, dynamic>>('/meals/$id', data: body);
    return Meal.fromJson(response.data!);
  });

  Future<void> deleteMeal(String id) =>
      guardApiCall(() => _dio.delete<void>('/meals/$id'));

  /// Metas (5.2): a atual, o histórico e os limites de segurança.
  Future<TargetsInfo> targets() => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>('/nutrition/targets');
    return TargetsInfo.fromJson(response.data!);
  });

  /// Valem a partir de hoje; todas nulas = sem metas.
  Future<TargetsInfo> saveTargets({
    int? kcal,
    int? proteinG,
    int? carbsG,
    int? fatG,
  }) => guardApiCall(() async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/nutrition/targets',
      data: {
        'kcal': kcal,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
      },
    );
    return TargetsInfo.fromJson(response.data!);
  });
}

/// "2026-11-24T12:30:00" (horário de parede, sem fuso).
String localDateTime(DateTime moment) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${apiDate(moment)}T${two(moment.hour)}:${two(moment.minute)}:00';
}

final nutritionApiProvider = Provider<NutritionApi>(
  (ref) => NutritionApi(ref.watch(dioProvider)),
);
