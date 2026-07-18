import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_token_storage.dart';
import '../domain/auth_session.dart';
import '../domain/drip_user.dart';

final class AuthRepository {
  AuthRepository(this._client, this._tokenStorage);

  final ApiClient _client;
  final SecureTokenStorage _tokenStorage;
  Future<void>? _googleInitialization;

  Future<AuthSession> googleSignIn() async {
    final webClientId = AppConfig.googleOAuthWebClientId;
    if (webClientId.isEmpty) {
      throw StateError(
        'Google sign-in is missing its client ID configuration.',
      );
    }

    await (_googleInitialization ??= GoogleSignIn.instance.initialize(
      serverClientId: webClientId,
    ));
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw StateError('Google sign-in is not supported on this device.');
    }

    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google did not return an ID token.');
    }

    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/auth/google',
      data: {'id_token': idToken},
    );
    return _persistSession(response.data!);
  }

  Future<DripUser> me(String token) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/v1/auth/me',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return DripUser.fromJson(response.data!);
  }

  Future<void> logout() => _tokenStorage.clear();
  Future<String?> savedAccessToken() => _tokenStorage.readAccessToken();

  Future<AuthSession> _persistSession(Map<String, dynamic> data) async {
    final session = AuthSession.fromJson(data);
    await _tokenStorage.saveAccessToken(session.accessToken);
    return session;
  }
}
