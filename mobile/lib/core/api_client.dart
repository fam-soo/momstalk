import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'constants.dart';

final _storage = FlutterSecureStorage();

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Content-Type': 'application/json'},
  ));

  // 요청마다 저장된 토큰 자동 첨부
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await _storage.read(key: AppConstants.tokenKey);
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) async {
      if (error.response?.statusCode == 401) {
        // 토큰 만료 → refresh 시도
        final refreshed = await _tryRefresh(dio);
        if (refreshed) {
          final token = await _storage.read(key: AppConstants.tokenKey);
          error.requestOptions.headers['Authorization'] = 'Bearer $token';
          final response = await dio.fetch(error.requestOptions);
          return handler.resolve(response);
        }
      }
      handler.next(error);
    },
  ));

  return dio;
});

Future<bool> _tryRefresh(Dio dio) async {
  try {
    final refreshToken = await _storage.read(key: AppConstants.refreshTokenKey);
    if (refreshToken == null) return false;

    final resp = await dio.post('/auth/refresh', data: {'refresh_token': refreshToken});
    final newToken = resp.data['access_token'] as String;
    await _storage.write(key: AppConstants.tokenKey, value: newToken);
    return true;
  } catch (_) {
    await _storage.deleteAll();
    return false;
  }
}
