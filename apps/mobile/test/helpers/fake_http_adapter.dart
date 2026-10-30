import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef FakeHandler = ResponseBody Function(RequestOptions options);

/// Adaptador HTTP em memória: os testes respondem sem rede nem servidor.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final FakeHandler handler;
  final List<RequestOptions> requests = [];

  static ResponseBody json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

Dio dioWith(FakeHttpAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'http://api.test/api/v1'))
      ..httpClientAdapter = adapter;
