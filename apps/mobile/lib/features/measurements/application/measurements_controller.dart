import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/measurements_api.dart';
import '../domain/measurements.dart';

/// Id da conta logada: ao trocar de conta, nada de uma pessoa aparece para outra.
String? _userId(Ref ref) => ref.watch(
  authControllerProvider.select(
    (auth) => switch (auth.value) {
      Authenticated(:final user) => user.id,
      _ => null,
    },
  ),
);

/// O começo de um período de [days] dias até hoje.
DateTime periodStart(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - (days - 1));
}

/// As medidas, unidades e limites (públicos).
final metricOptionsProvider = FutureProvider<List<MetricInfo>>(
  (ref) => ref.watch(measurementsApiProvider).options(),
);

/// As medidas dos últimos [days] dias (mais novas antes).
final measurementsProvider = FutureProvider.autoDispose
    .family<List<Measurement>, int>((ref, days) {
      _userId(ref);
      return ref.watch(measurementsApiProvider).list(periodStart(days));
    });

/// A tendência de uma medida nos últimos dias.
final trendProvider = FutureProvider.autoDispose
    .family<Trend, ({String metric, int days})>((ref, key) {
      _userId(ref);
      return ref
          .watch(measurementsApiProvider)
          .trend(key.metric, periodStart(key.days));
    });
