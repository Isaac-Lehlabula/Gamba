import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_client.dart';
import '../../onboarding/data/profile_repository.dart';

part 'account_repository.g.dart';

/// A failure the user can act on, with wording that's safe to show.
class AccountException implements Exception {
  const AccountException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AccountRepository {
  AccountRepository(this._dio, this._tokens);

  final Dio _dio;
  final TokenStore _tokens;

  Future<bool> isSignedIn() async => await _tokens.read() != null;

  Future<String?> signedInEmail() => _tokens.email();

  /// Creates an account; the local profile id is sent so this phone's records map onto it.
  Future<void> register(String email, String password, {required String localProfileId}) => _authenticate(
        '/api/v1/auth/register',
        {'email': email, 'password': password, 'localProfileId': localProfileId},
        email,
      );

  Future<void> signIn(String email, String password) =>
      _authenticate('/api/v1/auth/login', {'email': email, 'password': password}, email);

  /// Ends this phone's session. Local data stays on the phone.
  Future<void> signOut() async {
    final tokens = await _tokens.read();
    if (tokens != null) {
      try {
        await _dio.post<void>('/api/v1/auth/logout', data: {'refreshToken': tokens.refreshToken});
      } on DioException {
        // Signing out locally still matters when the server can't be reached.
      }
    }
    await _tokens.clear();
  }

  /// Starts deletion of the account and its backup on the server. Local data stays on the phone.
  Future<void> deleteAccount() async {
    try {
      await _dio.delete<void>('/api/v1/auth/account');
    } on DioException catch (e) {
      throw _friendly(e);
    }
    await _tokens.clear();
  }

  Future<void> _authenticate(String path, Map<String, dynamic> body, String email) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: body, options: AuthInterceptor.anonymous());
      await _tokens.save(authTokensFrom(response.data!), email: email.trim().toLowerCase());
    } on DioException catch (e) {
      throw _friendly(e);
    }
  }

  static AccountException _friendly(DioException e) => switch (e.response?.statusCode) {
        400 => const AccountException('Please check your email and password. Passwords need at least 8 characters.'),
        401 => const AccountException("That email and password don't match an account."),
        409 => const AccountException("An account couldn't be created with that email."),
        429 => const AccountException('Too many attempts. Please wait a minute and try again.'),
        _ when e.error is SignedOutException => const AccountException('Please sign in again.'),
        _ => const AccountException("Couldn't reach Reclaim's servers. Check your connection and try again."),
      };
}

@Riverpod(keepAlive: true)
AccountRepository accountRepository(Ref ref) => AccountRepository(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider));

/// The signed-in email, or null when using Reclaim without an account.
@riverpod
Future<String?> signedInEmail(Ref ref) async {
  final repo = ref.watch(accountRepositoryProvider);
  return await repo.isSignedIn() ? repo.signedInEmail() : null;
}

/// Kept here so the profile id can be sent when creating an account.
@riverpod
Future<String?> localProfileId(Ref ref) async => (await ref.watch(profileProvider.future))?.id;
