import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/coach.dart';

/// Conversas com a IA (docs/API.md §Fase 4). Só as do dono do token.
class CoachApi {
  const CoachApi(this._dio);

  final Dio _dio;

  /// A IA pode levar alguns segundos (várias consultas e o modelo): mais tempo
  /// que as outras chamadas antes de desistir.
  static const askTimeout = Duration(seconds: 90);

  Future<AiProviderInfo> provider() => guardApiCall(() async {
    final response = await _dio.get<Map<String, dynamic>>('/ai/provider');
    return AiProviderInfo.fromJson(response.data!);
  });

  Future<List<Conversation>> list() => guardApiCall(() async {
    final response = await _dio.get<List<dynamic>>('/ai/conversations');
    return response.data!
        .map((c) => Conversation.fromJson(c as Map<String, dynamic>))
        .toList();
  });

  Future<(Conversation, List<ChatMessage>)> get(String id) =>
      guardApiCall(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/ai/conversations/$id',
        );
        final data = response.data!;
        return (
          Conversation.fromJson(data),
          [
            for (final m in data['messages'] as List<dynamic>)
              ChatMessage.fromJson(m as Map<String, dynamic>),
          ],
        );
      });

  Future<Conversation> create({
    CoachScope scope = CoachScope.global,
    Map<String, Object?>? scopeRef,
    String? title,
  }) => guardApiCall(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/ai/conversations',
      data: {'scope': scope.code, 'scope_ref': ?scopeRef, 'title': ?title},
    );
    return Conversation.fromJson(response.data!);
  });

  Future<void> delete(String id) =>
      guardApiCall(() => _dio.delete<void>('/ai/conversations/$id'));

  /// Confirma (aplica) ou recusa uma proposta; devolve como ela ficou.
  Future<Proposal> decide(String proposalId, {required bool accept}) =>
      guardApiCall(() async {
        final action = accept ? 'accept' : 'reject';
        final response = await _dio.post<Map<String, dynamic>>(
          '/ai/proposals/$proposalId/$action',
        );
        return Proposal.fromJson(response.data!);
      });

  Future<CoachReply> ask(String id, String question) => guardApiCall(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/ai/conversations/$id/messages',
      data: {'content': question},
      options: Options(receiveTimeout: askTimeout),
    );
    return CoachReply.fromJson(response.data!);
  });
}

final coachApiProvider = Provider<CoachApi>(
  (ref) => CoachApi(ref.watch(dioProvider)),
);
