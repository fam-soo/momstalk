import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:go_router/go_router.dart';

import 'constants.dart';
import 'mock_interceptor.dart';
import 'nav_key.dart';

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

/// mock 모드 초기화 등 ProviderScope 밖에서 토큰을 쓸 때 사용
final tokenStorage = _storage;

final tokenStorageProvider = Provider<_TokenStorage>((_) => _storage);


final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConstants.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  if (AppConstants.mockMode) {
    dio.interceptors.add(MockInterceptor());
    return dio;
  }

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
        // 리프레시 실패(리프레시 토큰 만료 등) 또는 재시도 후에도 401 —
        // 세션이 완전히 끊긴 상태다. 예전엔 여기서 콘솔에 401만 남기고
        // 화면은 그대로 두어서, 사용자는 로그인된 화면(예: 관리자 페이지)을
        // 계속 보면서 왜 데이터가 하나도 안 불러와지는지 알 수 없었다.
        // 로그인 화면으로 강제 이동시켜 재로그인을 유도한다.
        _redirectToLoginOnSessionExpired();
      }
      handler.next(error);
    },
  ));

  return dio;
});

/// Dio 인터셉터 밖(예: package:http 사용 업로드)에서 401 발생 시 수동으로
/// 토큰을 갱신할 때 사용. 성공 시 true, 실패(리프레시 토큰 만료 등) 시 false.
Future<bool> tryRefreshToken(Dio dio) => _tryRefresh(dio);

void _redirectToLoginOnSessionExpired() {
  final ctx = rootNavKey.currentContext;
  if (ctx == null) return;
  final currentLoc = GoRouterState.of(ctx).uri.toString();
  if (currentLoc.startsWith('/auth')) return;
  ctx.go('/auth/login');
}

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
