/// Caminhos do app. Separado de `router.dart` para as telas navegarem sem importar o roteador.
abstract final class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const register = '/cadastro';
  static const home = '/inicio';
  static const status = '/status';
  static const onboarding = '/boas-vindas';
  static const profile = '/perfil';

  /// Edição de uma seção do perfil (ver ProfileSection).
  static String profileEdit(String section) => '/perfil/$section';

  /// Telas abertas a quem não entrou.
  static const public = {login, register};
}
