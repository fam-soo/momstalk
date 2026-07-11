import 'package:flutter/material.dart';
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
}

final notificationPrefsProvider =
    StateNotifierProvider<NotificationPrefsNotifier, Map<String, dynamic>?>((ref) {
  return NotificationPrefsNotifier(ref);
});

/// 게시판 화면 AppBar에 붙이는 "이 게시판 새 글 알림" 토글 버튼.
class BoardNotifyButton extends ConsumerWidget {
  final String prefKey; // notify_region / notify_school / notify_grade / notify_academy
  final String label;
  const BoardNotifyButton({super.key, required this.prefKey, required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    final on = prefs?[prefKey] as bool? ?? false;
    final color = on ? Theme.of(context).colorScheme.primary : null;
    return IconButton(
      icon: Icon(on ? Icons.notifications_active : Icons.notifications_none, color: color),
      tooltip: on ? '$label 새 글 알림 켜짐 (탭해서 끄기)' : '$label 새 글 알림 꺼짐 (탭해서 켜기)',
      onPressed: prefs == null
          ? null
          : () async {
              final result = await ref.read(notificationPrefsProvider.notifier).toggle(prefKey);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(result ? '$label 새 글 알림을 켰어요' : '$label 새 글 알림을 껐어요'),
                  duration: const Duration(seconds: 2),
                ));
              }
            },
    );
  }
}
