import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// 현재 로그인 유저 프로필(GET /auth/me). board_screen.dart에 있던 것을
/// core로 옮겨 router.dart(하단 네비 잠금 판단)에서도 순환 참조 없이 쓸 수
/// 있게 했다 — board_screen.dart가 router.dart를 이미 import하고 있어서,
/// router.dart가 board_screen.dart를 다시 import하면 순환 참조가 된다.
final userProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/auth/me');
  return Map<String, dynamic>.from(resp.data);
});
