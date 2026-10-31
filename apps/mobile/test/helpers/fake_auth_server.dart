import 'package:dio/dio.dart';
import 'package:evofit/core/auth/session_store.dart';

import 'fake_http_adapter.dart';

/// Armazenamento de tokens em memória (o Keystore não existe nos testes).
class InMemoryTokenStorage implements TokenStorage {
  InMemoryTokenStorage([this.value]);

  String? value;

  @override
  Future<String?> readRefreshToken() async => value;

  @override
  Future<void> writeRefreshToken(String token) async => value = token;

  @override
  Future<void> clear() async => value = null;
}

/// Imitação da API de autenticação com as mesmas regras de tokens do backend:
/// cada login/refresh gera um par novo e invalida o anterior.
class FakeAuthServer {
  FakeAuthServer({this.validRefreshToken});

  static const email = 'ana@exemplo.com';
  static const password = 'cavalo bateria grampo';

  late final adapter = FakeHttpAdapter(_handle);

  String? validAccessToken;
  String? validRefreshToken;
  bool offline = false;
  int refreshCalls = 0;
  int logoutCalls = 0;
  int _counter = 0;

  /// Perfil da conta. A conta padrão já concluiu o onboarding; o cadastro cria uma nova.
  Map<String, Object?> profile = onboardedProfile();
  Set<String> consents = {'terms_privacy'};

  /// Corpos de PATCH /me recebidos e consentimentos alterados, na ordem.
  final patches = <Map<String, Object?>>[];
  final consentCalls = <String>[];

  static Map<String, Object?> onboardedProfile() => {
    ...newProfile(),
    'primary_objective': 'gain_muscle',
    'preferred_modalities': ['strength'],
    'weekly_availability': {'days_per_week': 3, 'minutes_per_session': 45},
    'onboarding_completed_at': '2026-10-30T12:00:00Z',
  };

  static Map<String, Object?> newProfile() => {
    'display_name': 'Ana',
    'timezone': 'America/Sao_Paulo',
    'unit_system': 'metric',
    'secondary_objectives': <String>[],
    'preferred_modalities': <String>[],
    'equipment': <String>[],
    'dietary_preferences': <String>[],
    'limitation_tags': <String>[],
    'onboarding_completed_at': null,
  };

  static const options = {
    'objectives': [
      {'code': 'gain_muscle', 'label': 'Ganhar massa muscular'},
      {'code': 'lose_weight', 'label': 'Emagrecer'},
      {'code': 'general_health', 'label': 'Saúde geral'},
    ],
    'modalities': [
      {'code': 'strength', 'label': 'Musculação'},
      {'code': 'walk', 'label': 'Caminhada'},
    ],
    'equipment': [
      {'code': 'gym', 'label': 'Academia completa'},
      {'code': 'bands', 'label': 'Elásticos'},
    ],
    'dietary_preferences': <Object>[],
    'limitation_tags': [
      {'code': 'knee', 'label': 'Joelho'},
      {'code': 'lower_back', 'label': 'Lombar'},
    ],
    'experience_levels': [
      {'code': 'beginner', 'label': 'Iniciante'},
      {'code': 'advanced', 'label': 'Avançado'},
    ],
    'unit_systems': [
      {'code': 'metric', 'label': 'Métrico (kg, km)'},
    ],
    'sex_for_calculations': [
      {'code': 'unspecified', 'label': 'Prefiro não informar'},
    ],
  };

  /// Faz o access token atual expirar (o próximo uso recebe 401).
  void expireAccessToken() => validAccessToken = 'expirado';

  ResponseBody _handle(RequestOptions options) {
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'sem rede (teste)',
      );
    }
    final body = options.data is Map ? options.data as Map : const {};
    return switch ((options.method, options.path)) {
      ('POST', '/auth/login') =>
        body['email'] == email && body['password'] == password
            ? _issueTokens()
            : _problem(
                401,
                'invalid_credentials',
                'E-mail ou senha incorretos.',
              ),
      ('POST', '/auth/register') =>
        body['password'] == '1234567890'
            ? _problem(
                422,
                'validation_error',
                'Verifique os campos informados.',
                errors: [
                  {
                    'field': 'password',
                    'message': 'Essa senha é muito comum. Escolha outra.',
                  },
                ],
              )
            : _register(),
      ('POST', '/auth/refresh') => _refresh(body['refresh_token']),
      ('POST', '/auth/logout') => _logout(),
      ('GET', '/me') => _authorized(options) ? _me() : _invalidToken(),
      ('PATCH', '/me') =>
        _authorized(options)
            ? _patch(body.cast<String, Object?>())
            : _invalidToken(),
      ('GET', '/profile-options') => FakeHttpAdapter.json(
        200,
        FakeAuthServer.options,
      ),
      (final method, final path) when path.startsWith('/me/consents/') =>
        _authorized(options)
            ? _consent(method, path.split('/').last)
            : _invalidToken(),
      ('GET', '/health') => FakeHttpAdapter.json(200, {
        'status': 'ok',
        'database': 'ok',
        'version': '0.1.0',
        'environment': 'test',
      }),
      _ => _problem(404, 'not_found', 'Rota não encontrada no servidor falso.'),
    };
  }

  bool _authorized(RequestOptions options) =>
      options.headers['Authorization'] == 'Bearer $validAccessToken';

  ResponseBody _invalidToken() =>
      _problem(401, 'invalid_token', 'Sessão inválida ou expirada.');

  ResponseBody _register() {
    profile = newProfile();
    consents = {'terms_privacy'};
    return _issueTokens();
  }

  ResponseBody _me() => FakeHttpAdapter.json(200, {
    'id': '0192f0c0-0000-7000-8000-000000000001',
    'email': email,
    'status': 'active',
    'created_at': '2026-10-30T12:00:00Z',
    'profile': profile,
    'consents': [
      for (final kind in consents)
        {
          'kind': kind,
          'version': '2026-10',
          'granted_at': '2026-10-30T12:00:00Z',
        },
    ],
  });

  /// Mesma regra da API: dado de saúde novo só com o consentimento ativo.
  ResponseBody _patch(Map<String, Object?> body) {
    patches.add(body);
    final changes = {...body};
    final addsHealth =
        (changes['limitation_tags'] as List<dynamic>? ?? const []).isNotEmpty ||
        ((changes['limitations_note'] as String?) ?? '').isNotEmpty;
    if (addsHealth && !consents.contains('health_data')) {
      return _problem(403, 'consent_required', 'Autorize os dados de saúde.');
    }
    final completed = changes.remove('onboarding_completed') == true;
    profile = {...profile, ...changes};
    if (completed) {
      profile['onboarding_completed_at'] ??= '2026-10-31T12:00:00Z';
    }
    return _me();
  }

  ResponseBody _consent(String method, String kind) {
    consentCalls.add('$method $kind');
    if (method == 'PUT') {
      consents.add(kind);
      return FakeHttpAdapter.json(200, {
        'kind': kind,
        'version': '2026-10',
        'granted_at': '2026-10-31T12:00:00Z',
      });
    }
    consents.remove(kind);
    if (kind == 'health_data') {
      profile = {
        ...profile,
        'limitation_tags': <String>[],
        'limitations_note': null,
      };
    }
    return ResponseBody.fromString('', 204);
  }

  ResponseBody _refresh(Object? token) {
    refreshCalls++;
    if (token == null || token != validRefreshToken) {
      return _problem(401, 'invalid_refresh_token', 'Sessão expirada.');
    }
    return _issueTokens();
  }

  ResponseBody _logout() {
    logoutCalls++;
    validRefreshToken = null;
    return ResponseBody.fromString('', 204);
  }

  ResponseBody _issueTokens() {
    _counter++;
    validAccessToken = 'access-$_counter';
    validRefreshToken = 'refresh-$_counter';
    return FakeHttpAdapter.json(200, {
      'access_token': validAccessToken,
      'refresh_token': validRefreshToken,
      'token_type': 'bearer',
      'expires_in': 900,
      'refresh_expires_in': 2592000,
    });
  }

  static ResponseBody _problem(
    int status,
    String code,
    String detail, {
    List<Map<String, String>> errors = const [],
  }) => FakeHttpAdapter.json(status, {
    'type': 'https://evofit.local/errors/$code',
    'title': 'Erro',
    'status': status,
    'code': code,
    'detail': detail,
    'errors': errors,
    'request_id': 'teste',
  });
}
