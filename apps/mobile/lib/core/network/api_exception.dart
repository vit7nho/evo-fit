import 'package:dio/dio.dart';

enum ApiErrorKind { network, timeout, server, client, unknown }

/// Erro da API já traduzido para algo que a interface consegue exibir.
///
/// Lê o formato problem+json do backend (code, detail, errors, request_id).
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
    this.fieldErrors = const {},
    this.requestId,
  });

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          kind: ApiErrorKind.timeout,
          message: 'O servidor demorou para responder. Tente novamente.',
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          kind: ApiErrorKind.network,
          message:
              'Não foi possível conectar ao servidor. Verifique sua conexão.',
        );
      case DioExceptionType.badResponse:
        return _fromResponse(error.response!);
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return const ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Não foi possível concluir. Verifique sua conexão e tente novamente.',
        );
    }
  }

  static ApiException _fromResponse(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    final data = response.data;
    final problem = data is Map<String, dynamic> ? data : const {};

    final fieldErrors = <String, String>{
      for (final e in (problem['errors'] as List<dynamic>? ?? const []))
        if (e is Map && e['field'] is String && e['message'] is String)
          e['field'] as String: e['message'] as String,
    };
    final detail = problem['detail'];

    return ApiException(
      kind: status >= 500 ? ApiErrorKind.server : ApiErrorKind.client,
      statusCode: status,
      code: problem['code'] as String?,
      message: detail is String && detail.isNotEmpty
          ? detail
          : (status >= 500
                ? 'O servidor encontrou um problema. Tente novamente.'
                : 'Não foi possível concluir. Confira os dados e tente novamente.'),
      fieldErrors: fieldErrors,
      requestId: problem['request_id'] as String?,
    );
  }

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? code;
  final Map<String, String> fieldErrors;
  final String? requestId;

  @override
  String toString() => 'ApiException($kind, $statusCode, $code)';
}
