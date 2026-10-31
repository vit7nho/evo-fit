import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/domain/current_user.dart';
import '../domain/profile.dart';

/// Perfil, consentimentos e vocabulários (docs/API.md).
class ProfileApi {
  const ProfileApi(this._dio);

  final Dio _dio;

  /// Atualização parcial: só as chaves presentes em [changes] mudam; `null` limpa.
  Future<CurrentUser> update(Map<String, Object?> changes) =>
      guardApiCall(() async {
        final response = await _dio.patch<Map<String, dynamic>>(
          '/me',
          data: changes,
        );
        return CurrentUser.fromJson(response.data!);
      });

  Future<void> grantConsent(String kind) =>
      guardApiCall(() => _dio.put<void>('/me/consents/$kind'));

  Future<void> revokeConsent(String kind) =>
      guardApiCall(() => _dio.delete<void>('/me/consents/$kind'));

  Future<CurrentUser> me() => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>('/me');
    return CurrentUser.fromJson(response.data!);
  });

  Future<ProfileOptions> options() => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>('/profile-options');
    return ProfileOptions.fromJson(response.data!);
  });
}

final profileApiProvider = Provider<ProfileApi>(
  (ref) => ProfileApi(ref.watch(dioProvider)),
);

/// Vocabulários do perfil. Mantidos em memória enquanto o app está aberto.
final profileOptionsProvider = FutureProvider<ProfileOptions>(
  (ref) => ref.watch(profileApiProvider).options(),
);
