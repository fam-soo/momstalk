import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';

// 웹: SharedPreferences (localStorage) — Web Crypto API 의존성 없음
// 모바일: FlutterSecureStorage (Android Keystore / iOS Keychain)
class _TokenStorage {
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String?> read(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    return _secure.read(key: key);
  }

  Future<void> write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _secure.write(key: key, value: value);
    }
  }

  Future<void> deleteAll() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.tokenKey);
      await prefs.remove(AppConstants.refreshTokenKey);
    } else {
      await _secure.deleteAll();
    }
  }
}

final _storage = _TokenStorage();

final tokenStorageProvider = Provider<_TokenStorage>((_) => _storage);

/// router.dart / 하위 호환용 alias
final secureStorageProvider = tokenStorageProvider;

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await _storage.read(AppConstants.tokenKey);
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) async {
      final alreadyRetried = error.requestOptions.extra['_retried'] == true;
      if (error.response?.statusCode == 401 && !alreadyRetried) {
        final refreshed = await _tryRefresh(dio);
        if (refreshed) {
          try {
            final token = await _storage.read(AppConstants.tokenKey);
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            error.requestOptions.extra['_retried'] = true;
            final response = await dio.fetch(error.requestOptions);
            return handler.resolve(response);
          } catch (_) {
            await _storage.deleteAll();
          }
        }
      }
      handler.next(error);
    },
  ));

  return dio;
});

Future<bool> _tryRefresh(Dio dio) async {
  try {
    final refreshToken = await _storage.read(AppConstants.refreshTokenKey);
    if (refreshToken == null) return false;

    final resp = await dio.post('/auth/refresh', data: {'refresh_token': refreshToken});
    final newToken = resp.data['access_token'] as String;
    await _storage.write(AppConstants.tokenKey, newToken);
    return true;
  } catch (_) {
    await _storage.deleteAll();
    return false;
  }
}
