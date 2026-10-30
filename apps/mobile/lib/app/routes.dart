/// Caminhos do app. Separado de `router.dart` para as telas navegarem sem importar o roteador.
abstract final class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const register = '/cadastro';
  static const home = '/inicio';
  static const status = '/status';

  /// Telas abertas a quem não entrou.
  static const public = {login, register};
}
