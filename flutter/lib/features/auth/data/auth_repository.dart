import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_token_storage.dart';
import '../domain/auth_session.dart';
import '../domain/drip_user.dart';

final class AuthRepository {
  AuthRepository(this._client, this._tokenStorage);

  final ApiClient _client;
  final SecureTokenStorage _tokenStorage;

  Future<AuthSession> register({required String email, required String password, String? displayName}) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/auth/register',
      data: {'email': email, 'password': password, 'display_name': displayName},
    );
    return _persistSession(response.data!);
  }

  Future<AuthSession> login({required String email, required String password}) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/v1/auth/login',
      data: {'email': email, 'password': password},
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
