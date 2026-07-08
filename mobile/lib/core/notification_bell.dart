import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api_client.dart';

/// 모든 주요 화면의 AppBar 왼쪽 상단에 공통으로 붙는 알림 버튼.
/// 안읽은 알림 수를 배지로 보여주고, 탭하면 알림함으로 이동한 뒤 돌아오면
/// 배지를 다시 최신화한다.
class NotificationBellButton extends ConsumerStatefulWidget {
  const NotificationBellButton({super.key});

  @override
  ConsumerState<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends ConsumerState<NotificationBellButton> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/notifications/unread-count');
      if (mounted) setState(() => _unread = resp.data['count'] as int? ?? 0);
    } catch (_) {}
  }

  Future<void> _open() async {
    await context.push('/notifications');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Stack(clipBehavior: Clip.none, children: [
        const Icon(Icons.notifications_outlined),
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
      tooltip: '알림',
      onPressed: _open,
    );
  }
}
