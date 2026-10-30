import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_store.dart';
import '../../../core/network/api_exception.dart';
import '../data/auth_api.dart';
import '../domain/current_user.dart';

@immutable
sealed class AuthState {
  const AuthState();
}

class Authenticated extends AuthState {
  const Authenticated(this.user);

  final CurrentUser user;
}

class Unauthenticated extends AuthState {
  const Unauthenticated();
}

/// Estado da sessão do app inteiro. O roteador redireciona a partir dele.
///
/// - carregando: restaurando a sessão salva ao abrir o app;
/// - erro: não deu para falar com a API ao restaurar (a tela inicial oferece nova tentativa);
/// - dados: [Authenticated] ou [Unauthenticated].
class AuthController extends AsyncNotifier<AuthState> {
  SessionStore get _session => ref.read(sessionStoreProvider);
  AuthApi get _api => ref.read(authApiProvider);

  @override
  Future<AuthState> build() async {
    final subscription = ref
        .watch(sessionStoreProvider)
        .expirations
        .listen((_) => state = const AsyncData(Unauthenticated()));
    ref.onDispose(subscription.cancel);
    return _restore();
  }

  Future<AuthState> _restore() async {
    final refreshToken = await _session.loadRefreshToken();
    if (refreshToken == null) return const Unauthenticated();
    try {
      await _session.save(await _api.refresh(refreshToken));
      return Authenticated(await _api.me());
    } on ApiException catch (error) {
      if (error.kind == ApiErrorKind.client) {
        // Sessão salva não vale mais (expirada ou revogada): pede login de novo.
        await _session.clear();
        return const Unauthenticated();
      }
      // Sem conexão ou servidor fora: mantém o token salvo e deixa tentar de novo.
      rethrow;
    }
  }

  Future<void> retryRestore() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_restore);
  }

  /// Lança [ApiException] em caso de falha; a tela exibe a mensagem.
  Future<void> login({required String email, required String password}) =>
      _start(() => _api.login(email: email, password: password));

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required bool acceptTerms,
  }) => _start(
    () => _api.register(
      email: email,
      password: password,
      displayName: displayName,
      acceptTerms: acceptTerms,
    ),
  );

  Future<void> _start(Future<AuthTokens> Function() obtainTokens) async {
    await _session.save(await obtainTokens());
    try {
      state = AsyncData(Authenticated(await _api.me()));
    } on ApiException {
      await _session.clear();
      rethrow;
    }
  }

  /// Sai imediatamente no aparelho; avisar a API é melhor esforço (sem rede, o token
  /// expira sozinho no servidor).
  Future<void> logout() async {
    final refreshToken = _session.refreshToken;
    await _session.clear();
    state = const AsyncData(Unauthenticated());
    if (refreshToken == null) return;
    try {
      await _api.logout(refreshToken);
    } on ApiException {
      // Ignorado de propósito (ver acima).
    }
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
