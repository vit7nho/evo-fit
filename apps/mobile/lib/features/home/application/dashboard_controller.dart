import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/dashboard.dart';

/// GET /dashboard, só com os dados do dono do token.
class DashboardApi {
  const DashboardApi(this._dio);

  final Dio _dio;

  Future<Dashboard> fetch() => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>('/dashboard');
    return Dashboard.fromJson(response.data!);
  });
}

final dashboardApiProvider = Provider<DashboardApi>(
  (ref) => DashboardApi(ref.watch(dioProvider)),
);

/// O painel do Início. Descartado ao trocar de conta (os números de uma pessoa
/// nunca aparecem para outra); o Início pede de novo ao voltar de outra tela.
final dashboardProvider = FutureProvider.autoDispose<Dashboard>((ref) async {
  ref.watch(
    authControllerProvider.select(
      (auth) => switch (auth.value) {
        Authenticated(:final user) => user.id,
        _ => null,
      },
    ),
  );
  return ref.watch(dashboardApiProvider).fetch();
});
