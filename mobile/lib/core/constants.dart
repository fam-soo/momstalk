class AppConstants {
  // Android 에뮬레이터: 'http://10.0.2.2:8000/api/v1'
  // iOS 시뮬레이터:    'http://127.0.0.1:8000/api/v1'
  // 웹 / Windows:      'http://localhost:8000/api/v1'
  static const String baseUrl = 'http://localhost:8000/api/v1';

  static const String tokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';

  static const bool devMode = true; // 테스트 완료 후 false로 변경
}
