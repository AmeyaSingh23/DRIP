import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_token_storage.dart';
import '../data/auth_repository.dart';
import '../domain/auth_session.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
final secureTokenStorageProvider = Provider<SecureTokenStorage>(
  (ref) => SecureTokenStorage(),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(secureTokenStorageProvider),
  ),
);

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

final class AuthController extends AsyncNotifier<AuthSession?> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<AuthSession?> build() async {
    final token = await _repository.savedAccessToken();
    if (token == null) return null;
    try {
      final user = await _repository.me(token);
      return AuthSession(accessToken: token, user: user);
    } on DioException {
      await _repository.logout();
      return null;
    }
  }

  Future<String?> googleSignIn() async {
    state = const AsyncLoading();
    try {
      final session = await _repository.googleSignIn();
      state = AsyncData(session);
      return null;
    } catch (error) {
      state = const AsyncData(null);
      return _messageFor(error);
    }
  }

  Future<void> logout() async {
    final token = switch (state) {
      AsyncData(:final value) => value?.accessToken,
      _ => null,
    };
    state = const AsyncLoading();
    await _repository.logout(accessToken: token);
    state = const AsyncData(null);
  }

  Future<void> validateSession() async {
    final session = switch (state) {
      AsyncData(:final value) => value,
      _ => null,
    };
    if (session == null) return;
    try {
      await _repository.me(session.accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) return;
      await _repository.logout();
      state = const AsyncData(null);
    }
  }

  String _messageFor(Object error) {
    if (error is StateError) {
      return error.message.toString();
    }
    if (error is! DioException) {
      return 'Google sign-in did not finish. Please try again.';
    }
    final body = error.response?.data;
    if (body is Map<String, dynamic> && body['detail'] is String) {
      return body['detail'] as String;
    }
    return 'Could not reach DRIP. Check the API URL and your connection.';
  }
}
