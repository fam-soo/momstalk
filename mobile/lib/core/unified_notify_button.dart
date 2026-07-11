import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_prefs.dart';

/// 게시판 상단의 "이 게시판 새 글 알림 on/off" 버튼.
///
/// 예전엔 여기서 알림함으로도 이동할 수 있게 만들었는데(탭=알림함,
/// 길게 누르기=토글), 가장 흔한 동작(알림함 확인)에 단계가 늘어난다는
/// 피드백을 받았다. 알림함 이동은 새 알림이 실제로 도착했을 때 상단
/// 배너로 바로 보여주는 방식(core/router.dart의 _MainShellState)으로
/// 대체했고, 이 버튼은 다시 "이 게시판 알림 on/off" 단일 기능으로
/// 단순화했다 — 한 번 탭으로 바로 켜고 끌 수 있다.
class UnifiedNotifyButton extends ConsumerWidget {
  final String prefKey; // notify_region / notify_school / notify_grade / notify_academy
  final String label;
  const UnifiedNotifyButton({super.key, required this.prefKey, required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    final on = prefs?[prefKey] as bool? ?? false;
    final color = on ? Theme.of(context).colorScheme.primary : null;

    return IconButton(
      icon: Icon(on ? Icons.notifications_active : Icons.notifications_none, color: color),
      tooltip: on ? '$label 새 글 알림 끄기' : '$label 새 글 알림 켜기',
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
