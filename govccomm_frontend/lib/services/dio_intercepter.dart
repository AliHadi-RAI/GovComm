
import 'package:dio/dio.dart';
import 'secure_storage_service.dart';

class DioInterceptor extends Interceptor {
  final SecureStorageService _storage = SecureStorageService();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.retrieveKey('jwt_token');

    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    print('[HTTP REQUEST] ${options.method} => ${options.uri}');

    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    print('[HTTP ERROR] Status: ${err.response?.statusCode} | Message: ${err.message}');
    return handler.next(err);
  }
}