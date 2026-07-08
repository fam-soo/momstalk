import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';

// 관리자 페이지는 일반 사용자 토큰으로 인증 (users.is_admin = true 체크는 서버에서)
final adminDioProvider = Provider<Dio>((ref) {
  final storage = ref.read(tokenStorageProvider);
  final dio = Dio(BaseOptions(
    baseUrl: AppConstants.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await storage.read(AppConstants.tokenKey);
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    // 일반 dioProvider와 달리 이 인터셉터엔 401 시 토큰 재발급 로직이 없었다.
    // 액세스 토큰은 60분 만료라, 관리자 화면을 한 시간 넘게 열어두고 있으면
    // 이후 모든 요청이 401로 실패하면서 "데이터를 불러오지 못했습니다"만
    // 반복해서 보이는 문제가 있었다 — 일반 화면과 동일하게 리프레시 토큰으로
    // 자동 재시도하도록 맞춘다.
    onError: (error, handler) async {
      final alreadyRetried = error.requestOptions.extra['_retried'] == true;
      if (error.response?.statusCode == 401 && !alreadyRetried) {
        final refreshed = await tryRefreshToken(dio);
        if (refreshed) {
          try {
            final token = await storage.read(AppConstants.tokenKey);
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            error.requestOptions.extra['_retried'] = true;
            final response = await dio.fetch(error.requestOptions);
            return handler.resolve(response);
          } catch (_) {
            // fall through — 아래에서 원래 401 에러를 그대로 전달
          }
        }
      }
      handler.next(error);
    },
  ));

  return dio;
});
