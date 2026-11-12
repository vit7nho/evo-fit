import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/analytics_api.dart';
import '../domain/analytics.dart';
import '../domain/body.dart';

/// Tudo o que a tela Evolução mostra para um período.
@immutable
class Evolution {
  const Evolution({
    required this.overview,
    required this.sessions,
    required this.duration,
    this.run,
  });

  final Overview overview;

  /// Treinos e tempo comparados com o período anterior.
  final Comparison sessions;
  final Comparison duration;

  /// Só quando houve corrida no período.
  final EnduranceSummary? run;
}

/// Refaz o cálculo ao trocar de conta: os números de uma pessoa nunca aparecem
/// para outra.
void _watchAccount(Ref ref) => ref.watch(
  authControllerProvider.select(
    (auth) => switch (auth.value) {
      Authenticated(:final user) => user.id,
      _ => null,
    },
  ),
);

/// Meu Corpo de um período (3.6). Buscado de novo a cada visita.
final bodyProvider = FutureProvider.autoDispose
    .family<BodyStimulus, AnalyticsPeriod>((ref, period) async {
      _watchAccount(ref);
      return ref.watch(analyticsApiProvider).muscles(period);
    });

/// Detalhe de um músculo no período, com o período anterior.
final muscleDetailProvider = FutureProvider.autoDispose
    .family<MuscleDetail, (String, AnalyticsPeriod)>((ref, key) async {
      _watchAccount(ref);
      final (muscleId, period) = key;
      return ref.watch(analyticsApiProvider).muscle(muscleId, period);
    });

/// Buscado de novo a cada visita (os registros mudam o tempo todo) e descartado ao
/// trocar de conta: os números de uma pessoa nunca aparecem para outra.
final evolutionProvider = FutureProvider.autoDispose
    .family<Evolution, AnalyticsPeriod>((ref, period) async {
      _watchAccount(ref);
      final api = ref.watch(analyticsApiProvider);
      // Future.wait (e não `.wait` do record) para a tela receber a ApiException
      // original, com a mensagem da API.
      final results = await Future.wait<Object>([
        api.overview(period),
        api.compareWithPrevious(period, 'sessions'),
        api.compareWithPrevious(period, 'duration_s'),
      ]);
      final overview = results[0] as Overview;
      final sessions = results[1] as Comparison;
      final duration = results[2] as Comparison;
      final run = overview.modality('run') == null
          ? null
          : await api.endurance(period, 'run');
      return Evolution(
        overview: overview,
        sessions: sessions,
        duration: duration,
        run: run,
      );
    });
