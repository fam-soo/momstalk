import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// 게시판 종류별(지역/학교/학년/학원) "새 글 알림" on/off 상태를 앱 전역에서
/// 공유하는 캐시. 각 게시판 화면의 알람 버튼과 내정보 화면의 일괄 스위치가
/// 같은 상태를 보고 갱신하도록 Provider 하나로 관리한다.
class NotificationPrefsNotifier extends StateNotifier<Map<String, dynamic>?> {
  NotificationPrefsNotifier(this.ref) : super(null) {
    load();
  }
  final Ref ref;

  Future<void> load() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/notifications/prefs');
      state = Map<String, dynamic>.from(resp.data as Map);
    } catch (_) {}
  }

  /// 반환값: 반영된 최종 상태(실패 시 원래 값으로 롤백된 상태)
  Future<bool> toggle(String key) async {
    final current = state?[key] as bool? ?? false;
    final next = !current;
    state = {...?state, key: next}; // optimistic update
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.patch('/notifications/prefs', data: {key: next});
      state = Map<String, dynamic>.from(resp.data as Map);
      return state?[key] as bool? ?? next;
    } catch (_) {
      state = {...?state, key: current}; // 실패 시 롤백
      return current;
    }
  }

  /// 내정보의 "전체" 알림 스위치용 — 모든 세부 알림(댓글/지역/학교/학년/학원)을
  /// 한 번에 같은 값으로 맞춘다. 전체를 끄면 나머지도 다 꺼지고, 전체를 켜면
  /// 나머지도 다 켜진다(개별 조정은 그 이후에 따로 가능).
  static const _allKeys = ['notify_comment', 'notify_region', 'notify_school', 'notify_grade', 'notify_academy'];

  Future<void> setAll(bool value) async {
    final previous = state;
    state = {for (final k in _allKeys) k: value}; // optimistic
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.patch('/notifications/prefs', data: {for (final k in _allKeys) k: value});
      state = Map<String, dynamic>.from(resp.data as Map);
    } catch (_) {
      state = previous; // 실패 시 롤백
    }
  }
}

final notificationPrefsProvider =
    StateNotifierProvider<NotificationPrefsNotifier, Map<String, dynamic>?>((ref) {
  return NotificationPrefsNotifier(ref);
});
