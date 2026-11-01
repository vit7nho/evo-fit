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

  static const goals = '/metas';
  static const goalNew = '/metas/nova';

  /// Formulário de uma meta nova do tipo [kind].
  static String goalNewOfKind(String kind) => '/metas/nova/$kind';

  /// Edição de uma meta existente.
  static String goalEdit(String id) => '/metas/$id';

  static const exercises = '/exercicios';
  static const exerciseNew = '/exercicios/novo';
  static String exerciseDetail(String id) => '/exercicios/$id';
  static String exerciseEdit(String id) => '/exercicios/$id/editar';

  /// Telas abertas a quem não entrou.
  static const public = {login, register};
}
