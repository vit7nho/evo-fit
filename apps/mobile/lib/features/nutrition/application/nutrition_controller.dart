import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/nutrition_api.dart';
import '../domain/nutrition.dart';

/// Id da conta logada: ao sair ou trocar de conta, nada de uma pessoa aparece para
/// outra.
String? _userId(Ref ref) => ref.watch(
  authControllerProvider.select(
    (auth) => switch (auth.value) {
      Authenticated(:final user) => user.id,
      _ => null,
    },
  ),
);

/// As refeições e os totais de um dia (data sem hora); nulo = hoje no fuso do
/// perfil, decidido pela API.
final dailyNutritionProvider = FutureProvider.autoDispose
    .family<DailyNutrition, DateTime?>((ref, day) {
      _userId(ref);
      return ref.watch(nutritionApiProvider).daily(day);
    });

/// Alimentos do catálogo e próprios que combinam com a busca.
final foodSearchProvider = FutureProvider.autoDispose
    .family<List<Food>, String>((ref, query) {
      _userId(ref);
      return ref.watch(nutritionApiProvider).foods(query: query);
    });

/// As metas nutricionais (5.2).
final nutritionTargetsProvider = FutureProvider.autoDispose<TargetsInfo>((ref) {
  _userId(ref);
  return ref.watch(nutritionApiProvider).targets();
});

/// Hoje, sem hora (a chave do dia).
DateTime dayOf(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);
