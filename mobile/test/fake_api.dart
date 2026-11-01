import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:reclaim_app/core/network/api_client.dart';

typedef FakeHandler = (int status, Object? body) Function(RequestOptions request);

/// An in-memory API: requests go to handlers keyed by "METHOD /path", and every request is
/// recorded so tests can check what was sent.
class FakeApi implements HttpClientAdapter {
  final handlers = <String, FakeHandler>{};
  final requests = <RequestOptions>[];

  void on(String route, FakeHandler handler) => handlers[route] = handler;

  List<RequestOptions> sentTo(String route) =>
      requests.where((r) => '${r.method} ${r.uri.path}' == route).toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final route = '${options.method} ${options.uri.path}';
    final handler = handlers[route];
    final (status, body) = handler == null ? (404, null) : handler(options);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A Dio wired like the app's, but talking to [api].
Dio fakeDio(FakeApi api, TokenStore tokens) {
  final dio = Dio(BaseOptions(baseUrl: 'http://reclaim.test', contentType: 'application/json'))..httpClientAdapter = api;
  dio.interceptors.add(AuthInterceptor(tokens, dio));
  return dio;
}

Map<String, Object?> tokensJson(String access, String refresh) =>
    {'userId': 'u-1', 'accessToken': access, 'refreshToken': refresh, 'accessTokenExpiresAtUtc': '', 'refreshTokenExpiresAtUtc': ''};
