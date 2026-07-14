import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kakao_flutter_sdk_share/kakao_flutter_sdk_share.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api_client.dart';
import '../../../core/kst_time.dart';
import '../../../core/notification_prefs.dart';
import '../../../core/push_notifications.dart';
import '../../../core/refresh_bus.dart';
import '../../../core/router.dart';
import '../../../core/web_open_helper.dart';
import '../../board/screens/board_screen.dart';

// ──────────────────────────────────────────────────────────────────
// 프로필 메인 화면
// ──────────────────────────────────────────────────────────────────

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _profile;
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
      final resp = await dio.get('/auth/me');
      setState(() => _profile = Map<String, dynamic>.from(resp.data));
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await ref.read(tokenStorageProvider).deleteAll();
        if (mounted) ref.read(routerProvider).go('/auth/login');
        return;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(tokenStorageProvider).deleteAll();
    ref.invalidate(userProfileProvider);
    if (mounted) ref.read(routerProvider).go('/auth/login');
  }

  Future<void> _deleteAccount() async {
    // barrierDismissible: false — 외부 탭 실수로 dismiss 방지
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text(
          '탈퇴하면 모든 개인정보가 즉시 삭제됩니다.\n'
          '작성한 게시글·댓글은 익명 상태로 유지됩니다.\n\n'
          '정말 탈퇴하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('탈퇴'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/auth/me');
    } catch (_) {
      // 서버 오류여도 로컬 토큰 삭제 후 이동
    } finally {
      await ref.read(tokenStorageProvider).deleteAll();
      if (mounted) ref.read(routerProvider).go('/auth/login');
    }
  }

  Future<void> _generateInvite() async {
    final children = (_profile?['children'] as List? ?? []);
    int? selectedChildId;

    // 자녀가 2명 이상이면 어느 학교 링크를 공유할지 선택
    if (children.length > 1) {
      final activeChildId = _profile?['active_child_id'] as int?;
      selectedChildId = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('어느 학교 초대 링크를 만들까요?'),
          children: children.map<Widget>((c) {
            final id = c['id'] as int;
            final name = c['school_name'] as String? ?? '';
            final grade = c['grade'] as int? ?? 1;
            final isActive = id == activeChildId;
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, id),
              child: Row(children: [
                Expanded(child: Text('$name ($grade학년)', style: const TextStyle(fontSize: 14))),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('활성', style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.primary)),
                  ),
              ]),
            );
          }).toList(),
        ),
      );
      if (selectedChildId == null) return; // 취소
    }

    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/auth/invite/generate',
          data: selectedChildId != null ? {'child_id': selectedChildId} : {});
      final deeplink = resp.data['deeplink'] as String;
      final schoolName = resp.data['school_name'] as String? ?? '';
      final maxUses = resp.data['max_uses'] as int? ?? 10;
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => _InviteShareDialog(deeplink: deeplink, schoolName: schoolName, maxUses: maxUses),
      );
    } catch (e) {
      if (mounted) {
        final msg = e is DioException
            ? (e.response?.data?['detail'] as String? ?? '링크 생성 실패')
            : '링크 생성 실패: $e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  void _onTapSchoolChange(bool isPending, bool isMember) {
    if (isPending) {
      // 심사 중 → 심사 현황 화면으로
      context.push('/auth/pending');
      return;
    }
    if (!isMember) {
      // 미인증 lurker → 학교 검색 + 캡처 제출 흐름
      context.push('/auth/school-select');
      return;
    }
    // 정회원 → 스마트 검색으로 프로필 직접 변경
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditProfileScreen(profile: _profile!)),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    // 학교 게시판 등 다른 탭에서 활성 자녀를 바꾸면 여기도 최신 상태로 갱신한다.
    ref.listen<int>(boardRefreshSignal, (prev, next) {
      if (prev != null && prev != next) _load();
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 정보'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? const Center(child: Text('정보를 불러올 수 없습니다.'))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final isAdmin = (_profile!['is_admin'] as bool? ?? false) ||
        (_profile!['member_grade'] as String? ?? '') == 'admin';
    final isMember = isAdmin || (_profile!['member_grade'] as String? ?? 'lurker') == 'member';
    final isPending = !isAdmin && (_profile!['auth_pending'] as bool? ?? false);

    // active_child 기반 학교/지역 정보
    final activeChildId = _profile!['active_child_id'] as int?;
    final children = (_profile!['children'] as List?) ?? [];
    final activeChild = activeChildId != null
        ? children.firstWhere((c) => (c as Map)['id'] == activeChildId, orElse: () => null)
        : null;
    final displayRegion = (activeChild?['region'] ?? _profile!['region']) as String?;
    final displaySchool = (activeChild?['school_name'] ?? _profile!['school_name']) as String?;
    final displayGrade = (activeChild?['grade'] ?? _profile!['grade']) as int?;

    final needsSchoolVerification = _profile!['needs_school_verification'] as bool? ?? false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 미취학 → 초1 전환 유도 안내 ──────────────────
        if (needsSchoolVerification) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            color: Colors.orange.shade50,
            child: ListTile(
              leading: Icon(Icons.school_outlined, color: Colors.orange.shade700),
              title: const Text('자녀가 초등학교에 입학했나요?', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('학교 인증을 하면 학교·학년 게시판도 이용할 수 있어요.', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/add-child'),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── 관리자 패널 (최상단) ──────────────────────────
        if (isAdmin) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            color: const Color(0xFFE8F0FE),
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings, color: Color(0xFF4A90D9)),
              title: const Text('관리자 패널', style: TextStyle(color: Color(0xFF4A90D9), fontWeight: FontWeight.bold)),
              subtitle: const Text('대시보드, 신고 관리, 회원 관리', style: TextStyle(fontSize: 12, color: Color(0xFF6A9CC9))),
              trailing: const Icon(Icons.chevron_right, color: Color(0xFF4A90D9)),
              onTap: () => context.go('/admin'),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── 프로필 통합 카드 ──────────────────────────────
        // 예전엔 기본정보/학교변경/자녀관리/빠른실행이 카드 4개로 나뉘어
        // 있어서 화면 절반을 차지했다. 편집 기능이 없는 아바타 아이콘도
        // 자리만 차지하고, 학교 정보가 기본정보 카드와 변경 카드에 두 번
        // 보였다 — 하나의 카드로 합치고 중복을 없앴다.
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(_profile!['nickname'] ?? '닉네임 없음',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF4A90D9), borderRadius: BorderRadius.circular(4)),
                      child: const Text('관리자', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  const SizedBox(width: 8),
                  _TemperatureChip(celsius: (_profile!['temperature'] as num?)?.toDouble() ?? 36.5),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: '닉네임 변경',
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      await showDialog(context: context, builder: (_) => _NicknameDialog(nickname: _profile!['nickname'] ?? '', ref: ref));
                      _load();
                    },
                  ),
                ]),
                if (!isAdmin) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _onTapSchoolChange(isPending, isMember),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Icon(
                          isPending ? Icons.hourglass_top_rounded : (isMember ? Icons.school_outlined : Icons.verified_outlined),
                          size: 16, color: isPending ? Colors.orange : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isPending
                                ? '심사 진행 중 — 탭하여 현황 확인'
                                : !isMember
                                    ? '학부모 인증하기 (학교 선택)'
                                    : '${displayRegion ?? '-'} · ${displaySchool ?? '-'}${displayGrade != null ? ' ($displayGrade학년)' : ''}',
                            style: TextStyle(fontSize: 13, color: isPending ? Colors.orange.shade700 : null),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPending)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: const Text('심사중', style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600)),
                          )
                        else
                          Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                      ]),
                    ),
                  ),
                  if (isMember) ...[
                    const Divider(height: 1),
                    const SizedBox(height: 6),
                    _ChildrenSection(profile: _profile!, onChanged: _load),
                  ],
                  const Divider(height: 1),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    _QuickAction(icon: Icons.bookmark_outline, label: '스크랩', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScrapListScreen()))),
                    if (isMember && !isAdmin)
                      _QuickAction(icon: Icons.person_add_outlined, label: '친구초대', onTap: _generateInvite),
                  ]),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ── 알림 설정 ──────────────────────────────────
        const _NotificationSettingsCard(),
        const SizedBox(height: 8),

        // ── 서비스 정보 + 로그아웃/탈퇴 통합 (컴팩트) ──
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // 로그아웃 / 탈퇴
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _logout,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.logout, size: 16, color: Colors.orange.shade700),
                            const SizedBox(width: 6),
                            Text('로그아웃', style: TextStyle(color: Colors.orange.shade700, fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 36, color: Colors.grey.shade200),
                  Expanded(
                    child: InkWell(
                      onTap: _deleteAccount,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_remove_outlined, size: 16, color: Colors.red.shade400),
                            const SizedBox(width: 6),
                            Text('회원탈퇴', style: TextStyle(color: Colors.red.shade400, fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 1),
              // 서비스 정보 텍스트 버튼 행
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => context.push('/terms'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        foregroundColor: Colors.grey.shade500,
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      child: const Text('이용약관'),
                    ),
                    Text('|', style: TextStyle(color: Colors.grey.shade300, fontSize: 11)),
                    TextButton(
                      onPressed: () => context.push('/privacy'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        foregroundColor: Colors.grey.shade500,
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      child: const Text('개인정보처리방침'),
                    ),
                    Text('|', style: TextStyle(color: Colors.grey.shade300, fontSize: 11)),
                    Text('v1.0.0', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: Colors.grey.shade600),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 알림 설정 — 전체 푸시 on/off(브라우저 권한)와 게시판별(지역/학교/학년/
// 학원) 새 글 알림을 한 줄에 모아 보여준다. 예전엔 카드가 둘로 나뉘어
// 있어서 한눈에 비교하기 불편하다는 피드백을 반영했다. 전체 알림이
// 꺼지면 게시판 알림도 실제로는 오지 않으므로(브라우저 알림 자체가
// 안 뜸), 맨 앞에 "전체" 세그먼트로 두고 나머지 4개보다 시각적으로
// 강조한다.
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
            TextButton.icon(
              onPressed: () => context.push('/notifications'),
              icon: const Icon(Icons.inbox_outlined, size: 15),
              label: const Text('알림함', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
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

// ──────────────────────────────────────────────────────────────────
// 닉네임 변경 다이얼로그
// ──────────────────────────────────────────────────────────────────

class _NicknameDialog extends ConsumerStatefulWidget {
  final String nickname;
  final WidgetRef ref;
  const _NicknameDialog({required this.nickname, required this.ref});

  @override
  ConsumerState<_NicknameDialog> createState() => _NicknameDialogState();
}

class _NicknameDialogState extends ConsumerState<_NicknameDialog> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.nickname);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/auth/me/nickname', data: {'nickname': _ctrl.text.trim()});
      // 닉네임(실명 표시) 게시글을 이미 열어둔 게시판 목록(keep-alive)에
      // 예전 닉네임이 계속 보이던 문제 방지.
      bumpBoardRefresh(ref);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('변경 실패: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('닉네임 변경'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: '새 닉네임 (2~20자)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('저장'),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 자녀 관리 섹션
// ──────────────────────────────────────────────────────────────────

class _ChildrenSection extends ConsumerStatefulWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onChanged;
  const _ChildrenSection({required this.profile, required this.onChanged});

  @override
  ConsumerState<_ChildrenSection> createState() => _ChildrenSectionState();
}

class _ChildrenSectionState extends ConsumerState<_ChildrenSection> {
  bool _loading = false;

  List<dynamic> get _children => (widget.profile['children'] as List?) ?? [];
  int? get _activeChildId => widget.profile['active_child_id'] as int?;

  String _schoolTypeLabel(String? type) {
    switch (type) {
      case 'elementary': return '초';
      case 'middle': return '중';
      case 'high': return '고';
      default: return '';
    }
  }

  Future<void> _setActive(int childId) async {
    if (_activeChildId == childId) return;
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/auth/me/active-child/$childId');
      bumpBoardRefresh(ref); // 지역/학교/학원 탭도 바뀐 활성 자녀 기준으로 다시 불러오도록
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('전환 실패: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteChild(int childId, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('자녀 삭제'),
        content: Text('"$label" 자녀를 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/auth/me/children/$childId');
      // 활성 자녀가 삭제되면 학교/학년 게시판의 범위 자체가 바뀔 수 있어
      // _setActive와 동일하게 갱신 신호를 보낸다.
      bumpBoardRefresh(ref);
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }

  Future<void> _addChild() async {
    final result = await context.push<bool>('/profile/add-child');
    if (result == true) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 카드 껍데기 없이 상위(프로필 통합 카드) 안에 바로 얹히는 컴팩트한
    // 섹션 — 자녀가 1명뿐이어도 "추가" 동선은 항상 보여준다.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.child_care, size: 15, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text('자녀', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(width: 4),
              Text('(선택 시 전환 · 길게 눌러 삭제)', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              const Spacer(),
              if (_children.length < 5)
                TextButton.icon(
                  onPressed: _loading ? null : _addChild,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('추가', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                ),
            ],
          ),
          if (_children.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('등록된 자녀가 없습니다.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _children.map<Widget>((child) {
                final id = child['id'] as int;
                final isActive = id == _activeChildId;
                final schoolName = child['school_name'] as String? ?? '';
                final grade = child['grade'] as int?;
                final schoolType = _schoolTypeLabel(child['school_type'] as String?);
                final label = '$schoolName ${grade != null ? "$grade학년" : ""}($schoolType)';
                return GestureDetector(
                  onLongPress: () => _deleteChild(id, label),
                  child: FilterChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: isActive,
                    selectedColor: theme.colorScheme.primaryContainer,
                    checkmarkColor: theme.colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _setActive(id),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _SchoolTypeChip extends StatelessWidget {
  final String type;
  const _SchoolTypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      'elementary' => ('초', Colors.green),
      'middle' => ('중', Colors.blue),
      'high' => ('고', Colors.purple),
      _ => ('?', Colors.grey),
    };
    return CircleAvatar(
      radius: 16,
      backgroundColor: color.withOpacity(0.15),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 지역·학교·학년 변경 (정회원 전용 — 스마트 검색 방식)
// ──────────────────────────────────────────────────────────────────

class EditProfileScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> profile;
  const EditProfileScreen({super.key, required this.profile});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _searchCtrl = TextEditingController();
  String? _selectedType;
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selected;
  int _grade = 1;
  int? _classNum;
  bool _loading = false;
  bool _saving = false;
  bool _searched = false;

  static const _typeOptions = [
    (null, '전체'),
    ('elementary', '초'),
    ('middle', '중'),
    ('high', '고'),
  ];

  @override
  void initState() {
    super.initState();
    _grade = widget.profile['grade'] as int? ?? 1;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.length < 2) return;
    setState(() { _loading = true; _results = []; _selected = null; _searched = true; });
    try {
      final dio = ref.read(dioProvider);
      final params = <String, dynamic>{'q': q};
      if (_selectedType != null) params['school_type'] = _selectedType;
      final resp = await dio.get('/schools/search', queryParameters: params);
      setState(() => _results = List<Map<String, dynamic>>.from(resp.data));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('검색 오류: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _extractRegion(String address) {
    final parts = address.split(' ');
    if (parts.length >= 2) {
      final c = parts[1];
      if (c.endsWith('구') || c.endsWith('군')) return c;
    }
    return parts.isNotEmpty ? parts[0] : address;
  }

  Future<void> _save() async {
    if (_selected == null) return;
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      final address = _selected!['address'] as String? ?? '';
      final region = (_selected!['region'] as String? ?? '').isNotEmpty
          ? _selected!['region'] as String
          : _extractRegion(address);

      await dio.patch('/auth/me/profile', data: {
        'region': region,
        'school_code': _selected!['school_code'],
        'school_name': _selected!['school_name'],
        'grade': _grade,
        'school_type': _selected!['school_type'],
      });

      ref.invalidate(userProfileProvider);
      bumpBoardRefresh(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('정보가 변경되었습니다.')));
        Navigator.pop(context);
      }
    } catch (e) {
      final msg = e.toString().contains('429') || e.toString().contains('월 1회')
          ? '월 1회만 변경할 수 있습니다.'
          : '변경 실패: $e';
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int get _maxGrade => _selected?['school_type'] == 'elementary' ? 6 : 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('지역·학교·학년 변경')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 현재 정보 표시
          Container(
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text(
              '현재: ${widget.profile['region'] ?? '-'} · ${widget.profile['school_name'] ?? '-'} · ${widget.profile['grade'] ?? '-'}학년',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),

          // 검색바
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '학교명 또는 지역명 (예: 행복초, 강남구)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() { _results = []; _selected = null; _searched = false; });
                        },
                      )
                    : null,
              ),
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _search(),
            ),
          ),

          // 학교급 필터 칩
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 8,
              children: _typeOptions.map((opt) {
                final selected = _selectedType == opt.$1;
                return FilterChip(
                  label: Text(opt.$2),
                  selected: selected,
                  onSelected: (_) {
                    setState(() { _selectedType = opt.$1; _results = []; _selected = null; });
                    if (_searched) _search();
                  },
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ),

          if (_loading) const LinearProgressIndicator(),

          // 검색 결과
          Expanded(
            child: !_searched
                ? Center(
                    child: Text('새로 등록할 학교를 검색하세요',
                        style: TextStyle(color: Colors.grey.shade500)),
                  )
                : _results.isEmpty && !_loading
                    ? const Center(child: Text('검색 결과가 없어요.', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final s = _results[i];
                          final isSelected = _selected?['school_code'] == s['school_code'];
                          return ListTile(
                            leading: _SchoolTypeChip(type: s['school_type'] as String? ?? ''),
                            title: Text(s['school_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(s['address'] ?? '', style: const TextStyle(fontSize: 12)),
                            trailing: isSelected
                                ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                                : null,
                            selected: isSelected,
                            selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
                            onTap: () => setState(() { _selected = s; _grade = 1; _classNum = null; }),
                          );
                        },
                      ),
          ),

          // 학교 선택 후 학년/반 + 저장 버튼
          if (_selected != null) ...[
            const Divider(height: 1),
            Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('학년', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Row(
                    children: List.generate(_maxGrade, (i) {
                      final g = i + 1;
                      final selected = _grade == g;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i < _maxGrade - 1 ? 6 : 0),
                          child: GestureDetector(
                            onTap: () => setState(() => _grade = g),
                            child: Container(
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                                border: Border.all(
                                  color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$g학년',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                                  color: selected ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    value: _classNum,
                    decoration: const InputDecoration(labelText: '반 (선택)', border: OutlineInputBorder(), isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('선택 안함')),
                      ...List.generate(15, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}반'))),
                    ],
                    onChanged: (v) => setState(() => _classNum = v),
                  ),
                ],
              ),
            ),
          ],
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: FilledButton(
                onPressed: (_selected == null || _saving) ? null : _save,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('변경 저장', style: TextStyle(fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// 스크랩한 게시글 목록 화면
// ──────────────────────────────────────────────────────────────────

class ScrapListScreen extends ConsumerStatefulWidget {
  const ScrapListScreen({super.key});

  @override
  ConsumerState<ScrapListScreen> createState() => _ScrapListScreenState();
}

class _ScrapListScreenState extends ConsumerState<ScrapListScreen> {
  List<Map<String, dynamic>> _scraps = [];
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
      final resp = await dio.get('/posts/me/scraps');
      setState(() => _scraps = List<Map<String, dynamic>>.from(resp.data));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _boardTypeLabel(String type) {
    switch (type) {
      case 'region': return '지역';
      case 'school': return '학교';
      case 'grade': return '학년';
      case 'free': return '전체';
      default: return type;
    }
  }

  String _formatDate(String iso) {
    final kst = parseServerTimeToKst(iso);
    if (kst == null) return '';
    return '${kst.year}.${kst.month.toString().padLeft(2, '0')}.${kst.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('스크랩한 게시글')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _scraps.isEmpty
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bookmark_border, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('스크랩한 게시글이 없습니다.', style: TextStyle(color: Colors.grey)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _scraps.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final s = _scraps[i];
                      return InkWell(
                        onTap: () => context.push('/board/${s['id']}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _boardTypeLabel(s['board_type'] ?? ''),
                                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onPrimaryContainer),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(s['title'] ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                                      maxLines: 2, overflow: TextOverflow.ellipsis),
                                ),
                              ]),
                              const SizedBox(height: 4),
                              Row(children: [
                                const Icon(Icons.favorite_outline, size: 12, color: Colors.grey),
                                const SizedBox(width: 2),
                                Text('${s['like_count'] ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                const Text('  •  ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                const Icon(Icons.bookmark_outline, size: 12, color: Colors.grey),
                                const SizedBox(width: 2),
                                Text('${s['scrap_count'] ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                const Spacer(),
                                Text(_formatDate(s['created_at'] ?? ''), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ]),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _TemperatureChip extends StatelessWidget {
  final double celsius;
  const _TemperatureChip({required this.celsius});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    if (celsius >= 60) {
      color = Colors.red.shade600;
      icon = Icons.local_fire_department;
    } else if (celsius >= 40) {
      color = Colors.orange.shade600;
      icon = Icons.thermostat;
    } else if (celsius >= 30) {
      color = Colors.blue.shade600;
      icon = Icons.thermostat;
    } else {
      color = Colors.grey.shade500;
      icon = Icons.thermostat;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          '${celsius.toStringAsFixed(1)}°C',
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ── 초대 링크 공유 다이얼로그 ─────────────────────────────────────────

class _InviteShareDialog extends StatelessWidget {
  final String deeplink;
  final String schoolName;
  final int maxUses;
  const _InviteShareDialog({required this.deeplink, this.schoolName = '', this.maxUses = 10});

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: deeplink));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크가 복사되었습니다!'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _shareKakao(BuildContext context) async {
    final link = Link(
      webUrl: Uri.parse(deeplink),
      mobileWebUrl: Uri.parse(deeplink),
    );
    final template = FeedTemplate(
      content: Content(
        title: 'MomsTalk에 초대합니다!',
        description: '아래 버튼을 눌러 24시간 내 가입해주세요.',
        imageUrl: Uri.parse('https://momstalk.co.kr/icons/Icon-192.png'),
        link: link,
      ),
      buttons: [
        Button(title: '가입하기', link: link),
      ],
    );

    if (kIsWeb) {
      // 모바일 브라우저(특히 iOS Safari)는 await 이후에 새 창을 열면 사용자
      // 제스처가 끊긴 것으로 보고 팝업을 차단해 "반응 없음"처럼 보인다.
      // 클릭 즉시(await 이전) 빈 창을 먼저 열어두고, URL이 준비되면 그
      // 창의 location만 옮기는 방식으로 우회한다. PC 브라우저에서도 동일하게
      // 동작하므로 별도 분기 없이 항상 이 경로를 사용한다.
      final handle = openBlankWindow();
      try {
        final url = await WebSharerClient.instance.makeDefaultUrl(template: template);
        redirectWindow(handle, url.toString());
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: deeplink));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('링크를 복사했습니다. 카카오톡에 직접 붙여넣기 해주세요.')),
          );
        }
      }
      return;
    }

    try {
      if (await ShareClient.instance.isKakaoTalkSharingAvailable()) {
        await ShareClient.instance.shareDefault(template: template);
      } else {
        // KakaoTalk 미설치 → 카카오 공유 웹 페이지 열기
        final url = await WebSharerClient.instance.makeDefaultUrl(template: template);
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // SDK 공유 실패 시 클립보드 복사로 폴백
      await Clipboard.setData(ClipboardData(text: deeplink));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('링크를 복사했습니다. 카카오톡에 직접 붙여넣기 해주세요.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('초대 링크 생성 완료'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (schoolName.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '📍 $schoolName 학부모 초대 링크',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        Text(
          '아래 링크를 공유해 주세요.\n24시간 동안 최대 $maxUses명까지 함께 가입할 수 있어요.',
          style: const TextStyle(fontSize: 13, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(deeplink, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _copyLink(context),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('링크 복사'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFEE500),
                foregroundColor: const Color(0xFF3C1E1E),
              ),
              onPressed: () => _shareKakao(context),
              icon: const Icon(Icons.chat_bubble, size: 16),
              label: const Text('카카오톡 전달'),
            ),
          ),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
      ],
    );
  }
}
