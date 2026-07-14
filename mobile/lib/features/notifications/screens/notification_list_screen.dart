import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/kst_time.dart';
import '../../../core/notification_prefs.dart';
import '../../../core/push_notifications.dart';
import '../../../core/push_target.dart';
import '../../../core/refresh_bus.dart';

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
      bumpNotificationRefresh(ref);
    } catch (_) {}
  }

  Future<void> _onTap(Map<String, dynamic> n) async {
    if (n['is_read'] != true) {
      try {
        final dio = ref.read(dioProvider);
        await dio.post('/notifications/${n['id']}/read');
        if (mounted) setState(() => n['is_read'] = true);
        bumpNotificationRefresh(ref);
      } catch (_) {}
    }
    final data = n['data'] as Map?;
    final location = data == null ? null : pushTargetLocation(Map<String, dynamic>.from(data));
    if (location != null && mounted) context.push(location);
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'comment': return Icons.chat_bubble_outline;
      case 'new_post': return Icons.article_outlined;
      case 'new_academy_review': return Icons.storefront_outlined;
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
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: _NotificationSettingsCard(),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
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
        ),
      ]),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 알림 설정 — 전체 푸시 on/off(브라우저 권한)와 게시판별(지역/학교/학년/
// 학원) 새 글 알림을 한 줄에 모아 보여준다. 예전엔 내정보 탭에 있었는데,
// 게시판 알림 버튼이 전부 "알림함으로 이동"하는 방식으로 통일되면서
// 자연스럽게 알림함 화면 상단으로 옮겨왔다. 전체 알림이 꺼지면 게시판
// 알림도 실제로는 오지 않으므로(브라우저 알림 자체가 안 뜸), 맨 앞에
// "전체" 세그먼트로 두고 나머지 4개보다 시각적으로 강조한다.
// ──────────────────────────────────────────────────────────────────

class _NotificationSettingsCard extends ConsumerStatefulWidget {
  const _NotificationSettingsCard();

  @override
  ConsumerState<_NotificationSettingsCard> createState() => _NotificationSettingsCardState();
}

class _NotificationSettingsCardState extends ConsumerState<_NotificationSettingsCard> with WidgetsBindingObserver {
  PushStatus? _pushStatus;
  bool _pushBusy = false;

  static const _boardItems = [
    ('notify_comment', '댓글', Icons.chat_bubble_outline),
    ('notify_region', '지역', Icons.location_on_outlined),
    ('notify_school', '학교', Icons.school_outlined),
    ('notify_grade', '학년', Icons.groups_outlined),
    ('notify_academy', '학원', Icons.storefront_outlined),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 브라우저 알림 권한 설정을 바꾸고 탭으로 돌아왔을 때 최신 상태 반영
    if (state == AppLifecycleState.resumed) _refreshPush();
  }

  Future<void> _refreshPush() async {
    final s = await PushNotifications.status();
    if (mounted) setState(() => _pushStatus = s);
  }

  Future<void> _togglePush() async {
    final turnOn = _pushStatus != PushStatus.on;
    setState(() => _pushBusy = true);
    if (turnOn) {
      final ok = await PushNotifications.requestAndRegister(ref);
      if (mounted && !ok) {
        final blocked = await PushNotifications.status() == PushStatus.blocked;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          blocked
              ? '브라우저에서 알림이 차단되어 있어요. 주소창 옆 자물쇠 아이콘에서 알림을 허용해주세요.'
              : '알림 권한이 허용되지 않았어요.',
        )));
      }
    } else {
      await PushNotifications.disable(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('알림을 껐어요. 이 기기로는 더 이상 알림이 오지 않아요.')),
        );
      }
    }
    // "전체" 스위치는 나머지 세부 알림(댓글/지역/학교/학년/학원)도 같은
    // 값으로 함께 맞춘다 — 개별 조정은 그 이후에 따로 할 수 있다.
    await ref.read(notificationPrefsProvider.notifier).setAll(turnOn);
    await _refreshPush();
    if (mounted) setState(() => _pushBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(notificationPrefsProvider);
    final theme = Theme.of(context);

    final (pushIcon, pushColor, pushLabel, pushTappable) = switch (_pushStatus) {
      PushStatus.on => (Icons.notifications_active, Colors.green.shade600, 'ON', true),
      PushStatus.off => (Icons.notifications_off_outlined, Colors.grey.shade400, 'OFF', true),
      PushStatus.blocked => (Icons.notifications_off, Colors.red.shade400, '차단됨', false),
      PushStatus.unavailable || null => (Icons.notifications_none, Colors.grey.shade400, '지원안함', false),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.campaign_outlined, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Text('알림 설정', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
            ),
          ]),
          const SizedBox(height: 2),
          Text('전체를 꺼두면 새 댓글·좋아요·게시판 알림 모두 오지 않아요. 게시판별로는 새 글 알림만 따로 켤 수 있어요.',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
          const SizedBox(height: 10),
          Row(children: [
            _NotifySegment(
              icon: _pushBusy ? null : pushIcon,
              busy: _pushBusy,
              label: '전체',
              statusLabel: pushLabel,
              color: pushColor,
              onTap: (pushTappable && !_pushBusy) ? _togglePush : null,
            ),
            Container(width: 1, height: 40, color: Colors.grey.shade200, margin: const EdgeInsets.symmetric(horizontal: 2)),
            for (final (key, label, icon) in _boardItems)
              _NotifySegment(
                icon: icon,
                label: label,
                statusLabel: (prefs?[key] as bool? ?? false) ? 'ON' : 'OFF',
                color: (prefs?[key] as bool? ?? false) ? theme.colorScheme.primary : Colors.grey.shade400,
                onTap: prefs == null ? null : () => ref.read(notificationPrefsProvider.notifier).toggle(key),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _NotifySegment extends StatelessWidget {
  final IconData? icon;
  final bool busy;
  final String label;
  final String statusLabel;
  final Color color;
  final VoidCallback? onTap;
  const _NotifySegment({
    this.icon,
    this.busy = false,
    required this.label,
    required this.statusLabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            Container(
              width: 34, height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statusLabel == 'ON' ? color.withOpacity(0.12) : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 2),
            Text(statusLabel,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
          ]),
        ),
      ),
    );
  }
}
