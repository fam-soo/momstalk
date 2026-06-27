import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';

const _adminTokenKey = 'admin_token';

Future<String?> readAdminToken() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_adminTokenKey);
}

Future<void> writeAdminToken(String token) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_adminTokenKey, token);
}

Future<void> deleteAdminToken() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_adminTokenKey);
}

final adminDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConstants.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await readAdminToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
  ));

  return dio;
});
