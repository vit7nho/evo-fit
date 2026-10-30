import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Par de tokens devolvido por /auth/login, /auth/register e /auth/refresh.
@immutable
class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
  );

  final String accessToken;
  final String refreshToken;
}

/// Onde o refresh token sobrevive ao fechamento do app.
abstract interface class TokenStorage {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String token);
  Future<void> clear();
}

/// Android Keystore (via flutter_secure_storage). Nunca SharedPreferences.
class SecureTokenStorage implements TokenStorage {
  const SecureTokenStorage(this._storage);

  static const _key = 'evofit.refresh_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshToken() async {
    try {
      return await _storage.read(key: _key);
    } on Exception {
      // Chave do Keystore inválida (ex.: app restaurado em outro aparelho): recomeça a sessão.
      await clear();
      return null;
    }
  }

  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _key, value: token);

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } on Exception {
      // Nada a limpar ou armazenamento indisponível: não há o que fazer além de seguir.
    }
  }
}

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => const SecureTokenStorage(FlutterSecureStorage()),
);

/// Tokens da sessão atual. O access token fica só em memória (vale 15 min).
class SessionStore {
  SessionStore(this._storage);

  final TokenStorage _storage;
  final _expirations = StreamController<void>.broadcast();

  String? _accessToken;
  String? _refreshToken;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;

  /// Emite quando a API recusa a renovação: a interface volta para o login.
  Stream<void> get expirations => _expirations.stream;

  Future<String?> loadRefreshToken() async =>
      _refreshToken ??= await _storage.readRefreshToken();

  Future<void> save(AuthTokens tokens) async {
    _accessToken = tokens.accessToken;
    _refreshToken = tokens.refreshToken;
    await _storage.writeRefreshToken(tokens.refreshToken);
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.clear();
  }

  Future<void> expire() async {
    await clear();
    _expirations.add(null);
  }

  void dispose() => _expirations.close();
}

final sessionStoreProvider = Provider<SessionStore>((ref) {
  final store = SessionStore(ref.watch(tokenStorageProvider));
  ref.onDispose(store.dispose);
  return store;
});
