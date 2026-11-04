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

  /// Séries do usuário nesse exercício e os recordes.
  static String exerciseHistory(String id) => '/exercicios/$id/historico';

  static const templates = '/fichas';
  static const templateNew = '/fichas/nova';
  static String templateEdit(String id) => '/fichas/$id';

  /// Treino em andamento.
  static const session = '/treino';

  /// Treinos concluídos e recordes.
  static const history = '/historico';
  static String workoutDetail(String id) => '/historico/$id';

  /// Corridas, caminhadas, pedais e nados.
  static const activities = '/atividades';
  static const activityNew = '/atividades/nova';
  static String activityEdit(String id) => '/atividades/$id';

  /// Telas abertas a quem não entrou.
  static const public = {login, register};
}
