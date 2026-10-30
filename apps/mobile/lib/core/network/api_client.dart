import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_store.dart';
import '../config/app_config.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';

/// Transporte HTTP. `null` usa o padrão do dio; os testes substituem por um adaptador falso.
final httpClientAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

/// Cliente HTTP único do app. Os repositórios das features dependem dele via Riverpod.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final adapter = ref.watch(httpClientAdapterProvider);
  final session = ref.watch(sessionStoreProvider);

  Dio create() {
    final dio = Dio(
      BaseOptions(
        baseUrl: '${config.apiBaseUrl}/api/v1',
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/json'},
      ),
    );
    if (adapter != null) dio.httpClientAdapter = adapter;
    return dio;
  }

  // Sem interceptors: usado só para renovar a sessão e repetir a chamada que recebeu 401.
  final bare = create();
  final dio = create()
    ..interceptors.add(
      AuthInterceptor(
        session: session,
        retryClient: bare,
        refresher: (refreshToken) async {
          final response = await bare.post<Map<String, dynamic>>(
            '/auth/refresh',
            data: {'refresh_token': refreshToken},
          );
          return AuthTokens.fromJson(response.data!);
        },
      ),
    );
  ref.onDispose(() {
    dio.close();
    bare.close();
  });
  return dio;
});

/// Executa a chamada e converte qualquer falha do dio em [ApiException].
Future<T> guardApiCall<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (error) {
    throw ApiException.fromDio(error);
  }
}
