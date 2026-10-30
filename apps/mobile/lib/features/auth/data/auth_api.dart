import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_store.dart';
import '../../../core/network/api_client.dart';
import '../domain/current_user.dart';

/// Endpoints de autenticação e da conta (docs/API.md).
class AuthApi {
  const AuthApi(this._dio);

  final Dio _dio;

  Future<AuthTokens> register({
    required String email,
    required String password,
    required String displayName,
    required bool acceptTerms,
  }) => _tokens('/auth/register', {
    'email': email,
    'password': password,
    'display_name': displayName,
    'accept_terms': acceptTerms,
  });

  Future<AuthTokens> login({required String email, required String password}) =>
      _tokens('/auth/login', {'email': email, 'password': password});

  Future<AuthTokens> refresh(String refreshToken) =>
      _tokens('/auth/refresh', {'refresh_token': refreshToken});

  Future<void> logout(String refreshToken) => guardApiCall(
    () =>
        _dio.post<void>('/auth/logout', data: {'refresh_token': refreshToken}),
  );

  Future<CurrentUser> me() => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>('/me');
    return CurrentUser.fromJson(response.data!);
  });

  Future<AuthTokens> _tokens(String path, Map<String, Object> body) =>
      guardApiCall(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          path,
          data: body,
        );
        return AuthTokens.fromJson(response.data!);
      });
}

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(dioProvider)),
);
