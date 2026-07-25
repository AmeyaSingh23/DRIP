import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/secure_token_storage.dart';

final class ApiClient {
  ApiClient()
      : dio = Dio(
          BaseOptions(
            baseUrl: AppConfig.apiBaseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            headers: const {'Content-Type': 'application/json'},
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.readAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
      ),
    );
    dio.interceptors.add(RetryInterceptor(dio));
  }

  final Dio dio;
  final SecureTokenStorage _storage = SecureTokenStorage();
}

class RetryInterceptor extends Interceptor {
  final Dio dio;
  RetryInterceptor(this.dio);

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final requestOptions = err.requestOptions;
    final int attempt = requestOptions.extra['retry_attempt'] as int? ?? 0;
    if (attempt >= 1) {
      return handler.next(err);
    }

    bool shouldRetry = false;
    final isRead = requestOptions.method == 'GET';

    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.connectionError) {
      shouldRetry = true;
    } else if (err.type == DioExceptionType.badResponse) {
      final status = err.response?.statusCode;
      if (status != null) {
        if (isRead && (status == 502 || status == 503 || status == 504)) {
          shouldRetry = true;
        }
      }
    }

    if (shouldRetry) {
      requestOptions.extra['retry_attempt'] = attempt + 1;
      
      // One short retry for transient GET failures. POST requests, including
      // AI calls, are never retried here, so this cannot multiply provider usage.
      await Future.delayed(const Duration(milliseconds: 500));
      
      try {
        final response = await dio.fetch(requestOptions);
        return handler.resolve(response);
      } on DioException catch (retryErr) {
        return handler.next(retryErr);
      }
    }

    return handler.next(err);
  }
}
