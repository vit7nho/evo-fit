import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configuração de build. Nenhum segredo fica no app: só a URL pública da API.
class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  /// `10.0.2.2` é o computador host visto de dentro do emulador Android.
  factory AppConfig.fromEnvironment() => const AppConfig(
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000',
    ),
  );

  final String apiBaseUrl;
}

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);
