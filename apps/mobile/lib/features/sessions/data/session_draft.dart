import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Rascunho local do treino aberto (ADR-037): a última cópia que o servidor
/// devolveu e as alterações de séries que ainda não chegaram lá, na ordem.
class SessionDraft {
  const SessionDraft({
    required this.session,
    required this.receivedAt,
    this.ops = const [],
  });

  factory SessionDraft.fromJson(Map<String, dynamic> json) => SessionDraft(
    session: json['session'] as Map<String, dynamic>,
    receivedAt: DateTime.parse(json['received_at'] as String),
    ops: (json['ops'] as List<dynamic>).cast<Map<String, dynamic>>(),
  );

  /// O treino como a API devolveu (com as séries que já foram salvas lá).
  final Map<String, dynamic> session;

  /// Quando essa cópia chegou: base do tempo de treino ao reabrir sem conexão.
  final DateTime receivedAt;

  /// Fila de alterações pendentes: `create`, `update` e `delete` de séries.
  final List<Map<String, dynamic>> ops;

  Map<String, Object?> toJson() => {
    'session': session,
    'received_at': receivedAt.toIso8601String(),
    'ops': ops,
  };
}

/// Onde o rascunho sobrevive ao fechamento do app.
abstract interface class DraftStorage {
  Future<SessionDraft?> read(String userId);

  /// Grava; nulo apaga.
  Future<void> write(String userId, SessionDraft? draft);
}

/// Armazenamento seguro do aparelho (Android Keystore), o mesmo do login: as
/// séries são dados de treino da pessoa. Falhas viram "sem rascunho" — o treino
/// continua pela API.
class SecureDraftStorage implements DraftStorage {
  const SecureDraftStorage(this._storage);

  final FlutterSecureStorage _storage;

  static String _key(String userId) => 'evofit.session_draft.$userId';

  @override
  Future<SessionDraft?> read(String userId) async {
    try {
      final text = await _storage.read(key: _key(userId));
      if (text == null) return null;
      return SessionDraft.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String userId, SessionDraft? draft) async {
    try {
      if (draft == null) {
        await _storage.delete(key: _key(userId));
      } else {
        await _storage.write(
          key: _key(userId),
          value: jsonEncode(draft.toJson()),
        );
      }
    } on Object {
      // Sem armazenamento: o treino segue, só não sobrevive a fechar o app offline.
    }
  }
}

/// Em memória, para os testes (e para simular fechar e reabrir o app).
class InMemoryDraftStorage implements DraftStorage {
  final drafts = <String, String>{};

  @override
  Future<SessionDraft?> read(String userId) async {
    final text = drafts[userId];
    return text == null
        ? null
        : SessionDraft.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  @override
  Future<void> write(String userId, SessionDraft? draft) async {
    if (draft == null) {
      drafts.remove(userId);
    } else {
      drafts[userId] = jsonEncode(draft.toJson());
    }
  }
}

final draftStorageProvider = Provider<DraftStorage>(
  (ref) => const SecureDraftStorage(FlutterSecureStorage()),
);
