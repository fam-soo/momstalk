import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/kst_time.dart';
import '../../../core/push_target.dart';

/// 알림함 — FCM 푸시는 기기가 꺼져있거나 알림 권한이 없으면 놓치기 쉬워서,
/// 앱 안에서 지난 알림을 모아 다시 볼 수 있도록 내정보 탭에서 진입하는
/// 별도 화면으로 제공한다.
class NotificationListScreen extends ConsumerStatefulWidget {
  const NotificationListScreen({super.key});

  @override
  ConsumerState<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends ConsumerState<NotificationListScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/notifications');
      final data = Map<String, dynamic>.from(resp.data as Map);
      final items = (data['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() => _items = items);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/notifications/read-all');
      if (mounted) setState(() { for (final n in _items) n['is_read'] = true; });
    } catch (_) {}
  }

  Future<void> _onTap(Map<String, dynamic> n) async {
    if (n['is_read'] != true) {
      try {
        final dio = ref.read(dioProvider);
        await dio.post('/notifications/${n['id']}/read');
        if (mounted) setState(() => n['is_read'] = true);
      } catch (_) {}
    }
    final data = n['data'] as Map?;
    final location = data == null ? null : pushTargetLocation(Map<String, dynamic>.from(data));
    if (location != null && mounted) context.push(location);
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'comment': return Icons.chat_bubble_outline;
      case 'dm': return Icons.mail_outline;
      case 'auth_approved': return Icons.verified_outlined;
      case 'auth_rejected': return Icons.error_outline;
      default: return Icons.notifications_none;
    }
  }

  String _timeAgo(String? iso) => kstTimeAgo(iso);

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => n['is_read'] != true);
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림함'),
        actions: [
          if (hasUnread)
            TextButton(onPressed: _markAllRead, child: const Text('모두 읽음')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.notifications_none, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('아직 받은 알림이 없어요.', style: TextStyle(color: Colors.grey)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final n = _items[i];
                      final isRead = n['is_read'] == true;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isRead ? Colors.grey.shade200 : Theme.of(ctx).colorScheme.primaryContainer,
                          child: Icon(_iconFor(n['type'] as String? ?? ''),
                              size: 18, color: isRead ? Colors.grey : Theme.of(ctx).colorScheme.primary),
                        ),
                        title: Text(n['title'] as String? ?? '',
                            style: TextStyle(fontSize: 14, fontWeight: isRead ? FontWeight.normal : FontWeight.w700)),
                        subtitle: Text(
                          [
                            if ((n['body'] as String? ?? '').isNotEmpty) n['body'] as String,
                            _timeAgo(n['created_at'] as String?),
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isRead ? null : Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.primary, shape: BoxShape.circle),
                        ),
                        onTap: () => _onTap(n),
                      );
                    },
                  ),
                ),
    );
  }
}
