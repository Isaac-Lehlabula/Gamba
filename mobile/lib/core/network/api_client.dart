import 'dart:async';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../storage/secure_store.dart';

part 'api_client.g.dart';

/// Where the optional account API lives. Set with `--dart-define=RECLAIM_API_URL=https://...`.
/// The default reaches a backend running on the development machine from the Android emulator;
/// release builds must provide an HTTPS URL.
abstract final class ApiConfig {
  static const baseUrl = String.fromEnvironment('RECLAIM_API_URL', defaultValue: 'http://10.0.2.2:5000');
}

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken, required this.userId});

  final String accessToken;
  final String refreshToken;
  final String userId;
}

/// Account tokens and the signed-in email, kept only in secure storage.
class TokenStore {
  TokenStore(this._store);

  static const _access = 'reclaim.auth.access.v1';
  static const _refresh = 'reclaim.auth.refresh.v1';
  static const _user = 'reclaim.auth.user.v1';
  static const _email = 'reclaim.auth.email.v1';

  final SecureStore _store;

  Future<AuthTokens?> read() async {
    final access = await _store.read(_access);
    final refresh = await _store.read(_refresh);
    final user = await _store.read(_user);
    if (access == null || refresh == null || user == null) return null;
    return AuthTokens(accessToken: access, refreshToken: refresh, userId: user);
  }

  Future<String?> email() => _store.read(_email);

  Future<void> save(AuthTokens tokens, {String? email}) async {
    await _store.write(_access, tokens.accessToken);
    await _store.write(_refresh, tokens.refreshToken);
    await _store.write(_user, tokens.userId);
    if (email != null) await _store.write(_email, email);
  }

  Future<void> clear() async {
    for (final key in [_access, _refresh, _user, _email]) {
      await _store.delete(key);
    }
  }
}

/// Raised when the user needs to sign in again (no tokens, or the refresh token was rejected).
class SignedOutException implements Exception {
  const SignedOutException();
}

/// Adds the access token to requests, and on a 401 refreshes once (shared by concurrent
/// requests, since refresh tokens are single-use) and retries.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._tokens, this._dio)
      // Refreshing goes through a separate client: sending it through this queued interceptor
      // would deadlock when the refresh itself fails while the original 401 is being handled.
      : _refresher = Dio(_dio.options)..httpClientAdapter = _dio.httpClientAdapter;

  final TokenStore _tokens;
  final Dio _dio;
  final Dio _refresher;

  static const _retried = 'reclaim.retried';
  static const _anonymous = 'reclaim.anonymous';

  /// Marks a request as not needing an account (auth endpoints, public content).
  static Options anonymous([Options? options]) => (options ?? Options()).copyWith(extra: {_anonymous: true});

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra[_anonymous] != true) {
      final tokens = await _tokens.read();
      if (tokens == null) {
        return handler.reject(DioException(requestOptions: options, error: const SignedOutException()));
      }
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    if (err.response?.statusCode != 401 || request.extra[_anonymous] == true || request.extra[_retried] == true) {
      return handler.next(err);
    }
    final tokens = await _tokens.read();
    if (tokens == null) return handler.next(err);

    try {
      final refreshed = await _refresher.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: {'refreshToken': tokens.refreshToken},
      );
      await _tokens.save(authTokensFrom(refreshed.data!));
    } on DioException {
      // The refresh token was rejected (expired, revoked or reused): the session is over.
      await _tokens.clear();
      return handler.reject(DioException(requestOptions: request, error: const SignedOutException()));
    }

    final fresh = await _tokens.read();
    request
      ..headers['Authorization'] = 'Bearer ${fresh!.accessToken}'
      ..extra[_retried] = true;
    try {
      handler.resolve(await _dio.fetch<dynamic>(request));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

AuthTokens authTokensFrom(Map<String, dynamic> json) => AuthTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      userId: json['userId'] as String,
    );

@Riverpod(keepAlive: true)
TokenStore tokenStore(Ref ref) => TokenStore(ref.watch(secureStoreProvider));

@Riverpod(keepAlive: true)
Dio apiClient(Ref ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    contentType: 'application/json',
  ));
  dio.interceptors.add(AuthInterceptor(ref.watch(tokenStoreProvider), dio));
  return dio;
}
