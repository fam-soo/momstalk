import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api_client.dart';
import 'notification_prefs.dart';

/// 게시판 상단의 "알림함 이동"과 "이 게시판 새 글 알림 on/off"를 버튼
/// 하나로 합친 것. 예전엔 좌측에 전체 알림함 버튼, 우측에 게시판별 알림
/// 토글이 따로 있어서 종 아이콘이 두 개 나란히 보여 중복/혼란스럽다는
/// 피드백을 받았다. 이제 종 아이콘 하나만 있고, 탭하면 메뉴에서 "알림함
/// 열기"와 "이 게시판 알림 켜기/끄기"를 고를 수 있다 — 이 게시판 알림이
/// 켜져 있으면 종이 채워진 아이콘+강조색으로 표시돼 한눈에 구분된다.
class UnifiedNotifyButton extends ConsumerStatefulWidget {
  final String prefKey; // notify_region / notify_school / notify_grade / notify_academy
  final String label;
  const UnifiedNotifyButton({super.key, required this.prefKey, required this.label});

  @override
  ConsumerState<UnifiedNotifyButton> createState() => _UnifiedNotifyButtonState();
}

class _UnifiedNotifyButtonState extends ConsumerState<UnifiedNotifyButton> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refreshUnread();
  }

  Future<void> _refreshUnread() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/notifications/unread-count');
      if (mounted) setState(() => _unread = resp.data['count'] as int? ?? 0);
    } catch (_) {}
  }

  Future<void> _openInbox() async {
    await context.push('/notifications');
    _refreshUnread();
  }

  Future<void> _toggle() async {
    final result = await ref.read(notificationPrefsProvider.notifier).toggle(widget.prefKey);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result ? '${widget.label} 새 글 알림을 켰어요' : '${widget.label} 새 글 알림을 껐어요'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(notificationPrefsProvider);
    final on = prefs?[widget.prefKey] as bool? ?? false;
    final color = on ? Theme.of(context).colorScheme.primary : null;

    return PopupMenuButton<String>(
      tooltip: '알림',
      icon: Stack(clipBehavior: Clip.none, children: [
        Icon(on ? Icons.notifications_active : Icons.notifications_none, color: color),
        if (_unread > 0)
          Positioned(
            right: -2, top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(_unread > 9 ? '9+' : '$_unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
      ]),
      onSelected: (value) {
        if (value == 'inbox') {
          _openInbox();
        } else if (value == 'toggle') {
          _toggle();
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: 'inbox',
          child: Row(children: [
            Icon(Icons.inbox_outlined, size: 18),
            SizedBox(width: 10),
            Text('알림함 열기'),
          ]),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Row(children: [
            Icon(on ? Icons.notifications_off_outlined : Icons.notifications_active_outlined, size: 18),
            const SizedBox(width: 10),
            Text(on ? '${widget.label} 새 글 알림 끄기' : '${widget.label} 새 글 알림 켜기'),
          ]),
        ),
      ],
    );
  }
}
