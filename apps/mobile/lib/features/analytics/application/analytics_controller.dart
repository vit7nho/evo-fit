import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/analytics_api.dart';
import '../domain/analytics.dart';
import '../domain/body.dart';
import '../domain/compare.dart';

/// Tudo o que a tela Evolução mostra para um período.
@immutable
class Evolution {
  const Evolution({
    required this.overview,
    required this.sessions,
    required this.duration,
    this.endurance = const [],
  });

  final Overview overview;

  /// Treinos e tempo comparados com o período anterior.
  final Comparison sessions;
  final Comparison duration;

  /// Corrida, caminhada, ciclismo e natação com distância no período, na ordem
  /// do resumo (mais frequente primeiro).
  final List<EnduranceSummary> endurance;

  EnduranceSummary? get run =>
      endurance.where((e) => e.modality == 'run').firstOrNull;
}

const _endurance = {'run', 'walk', 'cycle', 'swim'};

/// Modalidades de resistência com distância registrada.
Iterable<String> _withDistance(Overview overview) => overview.modalities
    .where((m) => _endurance.contains(m.modality) && (m.distanceM ?? 0) > 0)
    .map((m) => m.modality);

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
      final endurance = await Future.wait([
        for (final modality in _withDistance(overview))
          api.endurance(period, modality),
      ]);
      return Evolution(
        overview: overview,
        sessions: sessions,
        duration: duration,
        endurance: endurance,
      );
    });

/// Comparativos (3.7): os indicadores gerais e, havendo nos períodos, os da
/// musculação e a distância e o pace de cada modalidade. Os números e o
/// percentual vêm da API (`/analytics/compare`), nunca de conta no app.
final compareProvider = FutureProvider.autoDispose
    .family<List<CompareRow>, PeriodPair>((ref, pair) async {
      _watchAccount(ref);
      final api = ref.watch(analyticsApiProvider);
      final overviews = await Future.wait([
        api.overview(pair.a),
        api.overview(pair.b),
      ]);
      final strength = overviews.any((o) => o.modality('strength') != null);
      final modalities = {for (final o in overviews) ..._withDistance(o)};
      final wanted = <(String, String?)>[
        ('sessions', null),
        ('active_days', null),
        ('duration_s', null),
        if (strength) ...[
          ('strength_sets', null),
          ('strength_volume_kg', null),
        ],
        for (final m in modalities) ...[
          ('distance_m', m),
          if (m == 'run' || m == 'walk') ('pace_s_per_km', m),
        ],
      ];
      final results = await Future.wait([
        for (final (metric, modality) in wanted)
          api.compare(metric, pair.a, pair.b, modality: modality),
      ]);
      return [
        for (final (i, (_, modality)) in wanted.indexed)
          CompareRow(results[i], modality: modality),
      ];
    });
