import 'package:dio/dio.dart';

import '../auth/session_store.dart';

typedef TokenRefresher = Future<AuthTokens> Function(String refreshToken);

/// Anexa o access token e, em um 401, renova a sessão uma vez e repete a chamada.
///
/// É um [QueuedInterceptor]: várias requisições que recebem 401 ao mesmo tempo geram uma
/// única renovação. A repetição usa [retryClient] (um Dio sem interceptors) para não
/// reentrar na fila — o que travaria o interceptor.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required this.session,
    required this.refresher,
    required this.retryClient,
  });

  final SessionStore session;
  final TokenRefresher refresher;
  final Dio retryClient;

  static bool _isAuthEndpoint(RequestOptions options) =>
      options.path.startsWith('/auth/');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = session.accessToken;
    if (token != null && !_isAuthEndpoint(options)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final refreshToken = session.refreshToken;
    if (err.response?.statusCode != 401 ||
        _isAuthEndpoint(options) ||
        refreshToken == null) {
      return handler.next(err);
    }

    try {
      // Outra requisição da fila pode já ter renovado: só renova se o token usado é o atual.
      final usedHeader = options.headers['Authorization'];
      if (session.accessToken == null ||
          usedHeader == 'Bearer ${session.accessToken}') {
        await session.save(await refresher(refreshToken));
      }
      options.headers['Authorization'] = 'Bearer ${session.accessToken}';
      return handler.resolve(await retryClient.fetch<dynamic>(options));
    } on DioException catch (refreshError) {
      if (refreshError.requestOptions.path == '/auth/refresh' &&
          refreshError.response?.statusCode == 401) {
        // Refresh recusado (expirado, revogado ou reutilizado): a sessão acabou.
        await session.expire();
        return handler.next(err);
      }
      // Falha de rede na renovação ou erro da própria repetição: repassa esse erro.
      return handler.next(refreshError);
    }
  }
}
