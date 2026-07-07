import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/kst_time.dart';
import '../admin_api.dart';

// ── 공통 유틸 ────────────────────────────────────────

String _timeAgo(String? iso) => kstTimeAgo(iso);

Widget _statusChip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );

// ── 메인 화면 ────────────────────────────────────────

class AdminHomeScreen extends ConsumerStatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  ConsumerState<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends ConsumerState<AdminHomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    const tabs = ['통계', '사용자', '신고', '콘텐츠', '설정'];
    const icons = [
      Icons.bar_chart_rounded,
      Icons.people_alt_outlined,
      Icons.report_problem_outlined,
      Icons.article_outlined,
      Icons.settings_outlined,
    ];
    const activeIcons = [
      Icons.bar_chart_rounded,
      Icons.people_alt,
      Icons.report_problem,
      Icons.article,
      Icons.settings,
    ];

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.admin_panel_settings, color: Color(0xFF4A90D9), size: 22),
        ),
        title: Text('관리자 · ${tabs[_tab]}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 20),
            tooltip: '사용자 화면',
            onPressed: () => context.go('/region'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          _StatsTab(),
          _UsersTab(),
          _ReportsTab(),
          _ContentTab(),
          _SettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        height: 60,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: List.generate(5, (i) => NavigationDestination(
          icon: Icon(icons[i], size: 22),
          selectedIcon: Icon(activeIcons[i], size: 22),
          label: tabs[i],
        )),
      ),
    );
  }
}

// ── 1. 통계 탭 ────────────────────────────────────────

class _StatsTab extends ConsumerStatefulWidget {
  const _StatsTab();

  @override
  ConsumerState<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends ConsumerState<_StatsTab> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(adminDioProvider);
      final resp = await dio.get('/admin/stats');
      setState(() => _data = Map<String, dynamic>.from(resp.data));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_data == null) return _errWidget(_load);
    final users = _data!['users'] as Map;
    final pending = _data!['pending'] as Map;
    final posts = _data!['posts'] as Map;
    final reviews = _data!['reviews'] as Map;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 긴급 알림
          if ((pending['captures'] as int) > 0 || (pending['reports'] as int) > 0)
            _AlertBanner(captures: pending['captures'] as int, reports: pending['reports'] as int),
          const SizedBox(height: 10),

          // 사용자 현황
          _SectionTitle('사용자'),
          _StatGrid([
            _StatItem('전체', '${users['total']}명', Icons.people, Colors.blue),
            _StatItem('정회원', '${users['member']}명', Icons.verified_user, Colors.green),
            _StatItem('눈팅', '${users['lurker']}명', Icons.visibility_off, Colors.grey),
            _StatItem('오늘 가입', '+${users['new_today']}명', Icons.person_add, Colors.teal),
            _StatItem('이번주', '+${users['new_week']}명', Icons.calendar_today, Colors.indigo),
            _StatItem('정지/차단', '${(users['suspended'] as int) + (users['banned'] as int)}명', Icons.block, Colors.red),
          ]),
          const SizedBox(height: 12),

          // 게시글 현황
          _SectionTitle('게시글'),
          _StatGrid([
            _StatItem('전체', '${posts['total']}건', Icons.article, Colors.purple),
            _StatItem('오늘', '+${posts['today']}건', Icons.today, Colors.deepPurple),
            _StatItem('이번주', '+${posts['week']}건', Icons.calendar_month, Colors.purple.shade300),
            _StatItem('블라인드', '${posts['hidden']}건', Icons.hide_source, Colors.orange),
          ]),
          const SizedBox(height: 12),

          // 학원 후기
          _SectionTitle('학원 후기'),
          _StatGrid([
            _StatItem('전체', '${reviews['total']}건', Icons.rate_review, Colors.cyan),
            _StatItem('블라인드', '${reviews['hidden']}건', Icons.hide_source, Colors.orange),
          ]),
          const SizedBox(height: 12),

          // 7일 가입 추이
          _SectionTitle('최근 7일 가입 추이'),
          _DailyChart(daily: List<Map<String, dynamic>>.from(_data!['daily_signup'] ?? [])),
        ],
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final int captures;
  final int reports;
  const _AlertBanner({required this.captures, required this.reports});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(
          [
            if (captures > 0) '캡처 심사 $captures건',
            if (reports > 0) '미처리 신고 $reports건',
          ].join(' · '),
          style: const TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w600),
        )),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
      );
}

class _StatItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatItem(this.label, this.value, this.icon, this.color);
}

class _StatGrid extends StatelessWidget {
  final List<_StatItem> items;
  const _StatGrid(this.items);

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.0,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (_, i) {
        final item = items[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: item.color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: item.color.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(children: [
                Icon(item.icon, size: 13, color: item.color),
                const SizedBox(width: 4),
                Text(item.label, style: TextStyle(fontSize: 10, color: item.color.withOpacity(0.8))),
              ]),
              const SizedBox(height: 2),
              Text(item.value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: item.color)),
            ],
          ),
        );
      },
    );
  }
}

class _DailyChart extends StatelessWidget {
  final List<Map<String, dynamic>> daily;
  const _DailyChart({required this.daily});

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) return const Padding(
      padding: EdgeInsets.all(12),
      child: Text('데이터 없음', style: TextStyle(color: Colors.grey, fontSize: 13)),
    );
    final maxVal = daily.map((d) => (d['count'] as int)).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: daily.map((d) {
          final cnt = d['count'] as int;
          final ratio = maxVal > 0 ? cnt / maxVal : 0.0;
          final dateStr = (d['date'] as String).substring(5); // MM-DD
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$cnt', style: const TextStyle(fontSize: 9, color: Colors.grey)),
                const SizedBox(height: 2),
                Container(
                  height: 60 * ratio + 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A90D9).withOpacity(0.7),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 2),
                Text(dateStr, style: const TextStyle(fontSize: 9, color: Colors.grey)),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── 2. 사용자 탭 ─────────────────────────────────────

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> with SingleTickerProviderStateMixin {
  late final TabController _tc = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tc,
          labelStyle: const TextStyle(fontSize: 13),
          tabs: const [Tab(text: '유저 목록'), Tab(text: '캡처 심사')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tc,
            children: const [_UserListPane(), _CapturesPane()],
          ),
        ),
      ],
    );
  }
}

class _UserListPane extends ConsumerStatefulWidget {
  const _UserListPane();

  @override
  ConsumerState<_UserListPane> createState() => _UserListPaneState();
}

class _UserListPaneState extends ConsumerState<_UserListPane> with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String q) async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(adminDioProvider);
      final resp = await dio.get('/admin/users', queryParameters: q.isNotEmpty ? {'q': q} : null);
      setState(() => _users = List<Map<String, dynamic>>.from(resp.data));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _action(int userId, String action, {String reason = '', int days = 0}) async {
    try {
      final dio = ref.read(adminDioProvider);
      if (action == 'approve') {
        await dio.post('/admin/users/$userId/approve');
      } else if (action == 'warn') {
        await dio.post('/admin/users/$userId/warn', data: {'reason': reason});
      } else if (action == 'suspend') {
        await dio.post('/admin/users/$userId/suspend', data: {'days': days, 'reason': reason});
      } else if (action == 'ban') {
        await dio.post('/admin/users/$userId/ban', data: {'reason': reason});
      } else if (action == 'unban') {
        await dio.post('/admin/users/$userId/unban');
      } else if (action == 'grant_trust') {
        await dio.post('/admin/users/$userId/grant-trust');
      } else if (action == 'revoke_trust') {
        await dio.post('/admin/users/$userId/revoke-trust');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('처리 완료')));
        await _load(_ctrl.text);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: TextField(
          controller: _ctrl,
          decoration: InputDecoration(
            hintText: '닉네임, 내부 ID 또는 카카오 ID 검색',
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: IconButton(icon: const Icon(Icons.send, size: 16), onPressed: () => _load(_ctrl.text)),
          ),
          onSubmitted: _load,
        ),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: ListView.builder(
          itemCount: _users.length,
          itemBuilder: (_, i) => _UserTile(user: _users[i], onAction: _action),
        ),
      ),
    ]);
  }
}

class _UserTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final Future<void> Function(int, String, {String reason, int days}) onAction;
  const _UserTile({required this.user, required this.onAction});

  Color _gradeColor(String g) => switch (g) {
    'member' => Colors.green,
    'lurker' => Colors.grey,
    _ => Colors.orange,
  };

  String _gradeLabel(String g) => switch (g) {
    'member' => '정회원',
    'lurker' => '눈팅',
    _ => g,
  };

  @override
  Widget build(BuildContext context) {
    final isBanned = user['is_banned'] as bool? ?? false;
    final isSuspended = user['suspended_until'] != null;
    final isTrusted = user['is_trusted'] as bool? ?? false;
    final grade = user['member_grade'] as String? ?? '';

    return ExpansionTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: _gradeColor(grade).withOpacity(0.15),
        child: Text(
          (user['nickname'] as String? ?? '?').characters.first,
          style: TextStyle(fontSize: 12, color: _gradeColor(grade), fontWeight: FontWeight.bold),
        ),
      ),
      title: Row(children: [
        Expanded(child: Text(user['nickname'] as String? ?? '-',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        _statusChip(_gradeLabel(grade), _gradeColor(grade)),
        if (isTrusted) ...[const SizedBox(width: 4), _statusChip('면제', Colors.teal)],
        if (isBanned) ...[const SizedBox(width: 4), _statusChip('차단', Colors.red)],
        if (isSuspended && !isBanned) ...[const SizedBox(width: 4), _statusChip('정지', Colors.orange)],
      ]),
      // 펼치지 않아도 핵심 통계가 2줄 안에 다 보이도록 구성 (카카오 ID는 비노출 — 필요하면 검색으로 조회)
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            '${user['school_name'] ?? '-'} · 가입 ${_timeAgo(user['created_at'] as String?)}'
            ' · 최근 접속 ${user['last_login_at'] != null ? _timeAgo(user['last_login_at'] as String?) : '기록 없음'}',
            style: const TextStyle(fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '접속 ${user['login_count'] ?? 0}회 · 게시글 ${user['post_count'] ?? 0}개'
            ' · 좋아요 ${user['like_count'] ?? 0}개 · 경고 ${user['warning_count'] ?? 0}회',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (grade == 'lurker')
                _ActionBtn('승인', Colors.green, () => onAction(user['id'] as int, 'approve')),
              if (!isBanned && !isSuspended) ...[
                _ActionBtn('경고', Colors.orange, () => _showReasonDialog(context, '경고 사유', (r) => onAction(user['id'] as int, 'warn', reason: r))),
                _ActionBtn('7일 정지', Colors.deepOrange, () => _showReasonDialog(context, '정지 사유', (r) => onAction(user['id'] as int, 'suspend', reason: r, days: 7))),
                _ActionBtn('30일 정지', Colors.red.shade300, () => _showReasonDialog(context, '정지 사유', (r) => onAction(user['id'] as int, 'suspend', reason: r, days: 30))),
                _ActionBtn('영구 차단', Colors.red, () => _showReasonDialog(context, '차단 사유', (r) => onAction(user['id'] as int, 'ban', reason: r))),
              ],
              if (isBanned || isSuspended)
                _ActionBtn('해제', Colors.blue, () => onAction(user['id'] as int, 'unban')),
              if (!isTrusted)
                _ActionBtn('인증면제 부여', Colors.teal, () => onAction(user['id'] as int, 'grant_trust'))
              else
                _ActionBtn('인증면제 해제', Colors.teal.shade200, () => onAction(user['id'] as int, 'revoke_trust')),
            ]),
          ]),
        ),
      ],
    );
  }

  Widget _ActionBtn(String label, Color color, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ),
      );

  void _showReasonDialog(BuildContext context, String title, void Function(String) onConfirm) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '사유 입력', border: OutlineInputBorder(), isDense: true),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm(ctrl.text);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}

// ── 캡처 심사 패널 ─────────────────────────────────────

class _CapturesPane extends ConsumerStatefulWidget {
  const _CapturesPane();

  @override
  ConsumerState<_CapturesPane> createState() => _CapturesPaneState();
}

class _CapturesPaneState extends ConsumerState<_CapturesPane> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  final Map<int, Uint8List> _imageCache = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(adminDioProvider);
      final resp = await dio.get('/admin/captures');
      setState(() => _items = List<Map<String, dynamic>>.from(resp.data));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<Uint8List?> _fetchImage(int id) async {
    if (_imageCache.containsKey(id)) return _imageCache[id];
    try {
      final dio = ref.read(adminDioProvider);
      final resp = await dio.get('/admin/captures/$id/image',
          options: Options(responseType: ResponseType.bytes));
      final bytes = Uint8List.fromList(resp.data as List<int>);
      _imageCache[id] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _approve(int id) async {
    try {
      final dio = ref.read(adminDioProvider);
      await dio.post('/admin/captures/$id/approve');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('승인 완료')));
        await _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  Future<void> _reject(int id) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('거절 사유', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '사유 입력', border: OutlineInputBorder(), isDense: true),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('거절'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      final dio = ref.read(adminDioProvider);
      await dio.post('/admin/captures/$id/reject', data: {'reason': reason});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('거절 완료')));
        await _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return const Center(child: Text('대기 중인 캡처가 없습니다.', style: TextStyle(color: Colors.grey)));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final c = _items[i];
          final id = c['id'] as int;
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(c['nickname'] as String? ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 6),
                  if ((c['capture_type'] as String? ?? 'initial') == 'child_add')
                    _statusChip('자녀 추가', Colors.purple)
                  else
                    _statusChip('신규 가입', Colors.blue),
                  const Spacer(),
                  Text(_timeAgo(c['created_at'] as String?),
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
                const SizedBox(height: 4),
                Text('${c['input_school_name']} · ${c['input_grade']}학년${c['input_class_num'] != null ? ' ${c['input_class_num']}반' : ''}',
                    style: const TextStyle(fontSize: 12)),
                if (c['has_image'] == true) ...[
                  const SizedBox(height: 8),
                  FutureBuilder<Uint8List?>(
                    future: _fetchImage(id),
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                      }
                      if (snap.data == null) return const Text('이미지 없음', style: TextStyle(color: Colors.grey, fontSize: 12));
                      return GestureDetector(
                        onTap: () => _showFullImage(context, snap.data!),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(snap.data!, height: 100, width: double.infinity, fit: BoxFit.cover),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reject(id),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        minimumSize: const Size.fromHeight(34),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('거절', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _approve(id),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(34),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('승인', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  void _showFullImage(BuildContext context, Uint8List bytes) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes),
        ),
      ),
    );
  }
}

// ── 3. 신고 탭 ────────────────────────────────────────

class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab();

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _filter = 'pending';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(adminDioProvider);
      final resp = await dio.get('/admin/reports', queryParameters: {'status_filter': _filter});
      setState(() => _items = List<Map<String, dynamic>>.from(resp.data));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _review(int id, String action) async {
    String reason = '';
    if (action != 'cleared') {
      final ctrl = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('처리 사유', style: TextStyle(fontSize: 15)),
          content: TextField(controller: ctrl, decoration: const InputDecoration(
            border: OutlineInputBorder(), isDense: true)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('확인')),
          ],
        ),
      );
      if (result == null) return;
      reason = result;
    }
    try {
      final dio = ref.read(adminDioProvider);
      await dio.post('/admin/reports/$id/review', data: {'action': action, 'reason': reason});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('처리 완료')));
        await _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          for (final f in ['pending', 'actioned', 'dismissed'])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(switch(f) {
                  'pending' => '미처리',
                  'actioned' => '처리됨',
                  _ => '기각',
                }, style: const TextStyle(fontSize: 12)),
                selected: _filter == f,
                onSelected: (_) { _filter = f; _load(); },
                visualDensity: VisualDensity.compact,
              ),
            ),
        ]),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: _items.isEmpty && !_loading
            ? const Center(child: Text('신고 없음', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: _items.length,
                itemBuilder: (_, i) => _ReportCard(item: _items[i], onReview: _review),
              ),
      ),
    ]);
  }
}

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final Future<void> Function(int, String) onReview;
  const _ReportCard({required this.item, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final id = item['id'] as int;
    final targetType = item['target_type'] as String;
    final category = item['category'] as String? ?? '';
    final preview = item['content_preview'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _statusChip(targetType == 'post' ? '게시글' : '댓글', Colors.blue),
            const SizedBox(width: 6),
            _statusChip(category, Colors.purple),
            const Spacer(),
            Text(_timeAgo(item['created_at'] as String?),
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, height: 1.4)),
            ),
          ],
          if ((item['reason'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('신고 사유: ${item['reason']}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _Chip('기각', Colors.grey, () => onReview(id, 'cleared')),
            _Chip('경고', Colors.orange, () => onReview(id, 'warn')),
            _Chip('7일 정지', Colors.deepOrange, () => onReview(id, 'suspend_7d')),
            _Chip('30일 정지', Colors.red.shade300, () => onReview(id, 'suspend_30d')),
            _Chip('영구 차단', Colors.red, () => onReview(id, 'ban')),
          ]),
        ]),
      ),
    );
  }

  Widget _Chip(String label, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ),
      );
}

// ── 4. 콘텐츠 탭 ─────────────────────────────────────

class _ContentTab extends ConsumerStatefulWidget {
  const _ContentTab();

  @override
  ConsumerState<_ContentTab> createState() => _ContentTabState();
}

class _ContentTabState extends ConsumerState<_ContentTab> with SingleTickerProviderStateMixin {
  late final TabController _tc = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabBar(
        controller: _tc,
        labelStyle: const TextStyle(fontSize: 12),
        tabs: const [Tab(text: '게시글'), Tab(text: '댓글'), Tab(text: '학원 후기')],
      ),
      Expanded(
        child: TabBarView(
          controller: _tc,
          children: const [
            _PostListPane(),
            _CommentListPane(),
            _ReviewListPane(),
          ],
        ),
      ),
    ]);
  }
}

// ── 게시글 목록 ────────────────────────────────────────

class _PostListPane extends ConsumerStatefulWidget {
  const _PostListPane();

  @override
  ConsumerState<_PostListPane> createState() => _PostListPaneState();
}

class _PostListPaneState extends ConsumerState<_PostListPane> with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  String _filter = 'all';
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _page = 1;
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _page = 1;
    setState(() => _loading = true);
    try {
      final dio = ref.read(adminDioProvider);
      final resp = await dio.get('/admin/posts', queryParameters: {
        if (_ctrl.text.isNotEmpty) 'q': _ctrl.text,
        'filter': _filter,
        'page': _page,
      });
      final data = resp.data as Map;
      setState(() {
        _total = data['total'] as int;
        _items = List<Map<String, dynamic>>.from(data['items']);
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _hide(int id, bool hide) async {
    try {
      final dio = ref.read(adminDioProvider);
      await dio.post('/admin/posts/$id/${hide ? 'hide' : 'unhide'}');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('게시글 삭제', style: TextStyle(fontSize: 15)),
        content: const Text('복구할 수 없습니다. 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final dio = ref.read(adminDioProvider);
      await dio.delete('/admin/posts/$id');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      _ContentFilter(
        ctrl: _ctrl,
        filter: _filter,
        filters: const {'all': '전체', 'hidden': '블라인드', 'reported': '신고'},
        onFilter: (f) { _filter = f; _load(reset: true); },
        onSearch: () => _load(reset: true),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          Text('총 $_total건', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const Spacer(),
          if (_page > 1) TextButton(onPressed: () { _page--; _load(); }, child: const Text('이전', style: TextStyle(fontSize: 12))),
          if (_items.length == 30) TextButton(onPressed: () { _page++; _load(); }, child: const Text('다음', style: TextStyle(fontSize: 12))),
        ]),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: _items.length,
          itemBuilder: (_, i) {
            final p = _items[i];
            final isHidden = p['is_hidden'] as bool? ?? false;
            return _ContentCard(
              title: p['title'] as String? ?? '-',
              subtitle: '${p['board_type']} · ${p['author_nickname']}',
              body: p['content'] as String? ?? '',
              timeAgo: _timeAgo(p['created_at'] as String?),
              isHidden: isHidden,
              reportCount: p['report_count'] as int? ?? 0,
              onHide: () => _hide(p['id'] as int, !isHidden),
              onDelete: () => _delete(p['id'] as int),
            );
          },
        ),
      ),
    ]);
  }
}

// ── 댓글 목록 ─────────────────────────────────────────

class _CommentListPane extends ConsumerStatefulWidget {
  const _CommentListPane();

  @override
  ConsumerState<_CommentListPane> createState() => _CommentListPaneState();
}

class _CommentListPaneState extends ConsumerState<_CommentListPane> with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  String _filter = 'all';
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _page = 1;
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _page = 1;
    setState(() => _loading = true);
    try {
      final dio = ref.read(adminDioProvider);
      final resp = await dio.get('/admin/comments', queryParameters: {
        if (_ctrl.text.isNotEmpty) 'q': _ctrl.text,
        'filter': _filter,
        'page': _page,
      });
      final data = resp.data as Map;
      setState(() {
        _total = data['total'] as int;
        _items = List<Map<String, dynamic>>.from(data['items']);
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _hide(int id, bool hide) async {
    try {
      final dio = ref.read(adminDioProvider);
      await dio.post('/admin/comments/$id/${hide ? 'hide' : 'unhide'}');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('댓글 삭제', style: TextStyle(fontSize: 15)),
        content: const Text('복구할 수 없습니다. 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final dio = ref.read(adminDioProvider);
      await dio.delete('/admin/comments/$id');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      _ContentFilter(
        ctrl: _ctrl,
        filter: _filter,
        filters: const {'all': '전체', 'hidden': '블라인드', 'reported': '신고'},
        onFilter: (f) { _filter = f; _load(reset: true); },
        onSearch: () => _load(reset: true),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          Text('총 $_total건', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const Spacer(),
          if (_page > 1) TextButton(onPressed: () { _page--; _load(); }, child: const Text('이전', style: TextStyle(fontSize: 12))),
          if (_items.length == 30) TextButton(onPressed: () { _page++; _load(); }, child: const Text('다음', style: TextStyle(fontSize: 12))),
        ]),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: _items.length,
          itemBuilder: (_, i) {
            final c = _items[i];
            final isHidden = c['is_hidden'] as bool? ?? false;
            return _ContentCard(
              title: '게시글 #${c['post_id']}의 댓글',
              subtitle: c['author_nickname'] as String? ?? '-',
              body: c['content'] as String? ?? '',
              timeAgo: _timeAgo(c['created_at'] as String?),
              isHidden: isHidden,
              reportCount: c['report_count'] as int? ?? 0,
              onHide: () => _hide(c['id'] as int, !isHidden),
              onDelete: () => _delete(c['id'] as int),
            );
          },
        ),
      ),
    ]);
  }
}

// ── 학원 후기 목록 ────────────────────────────────────

class _ReviewListPane extends ConsumerStatefulWidget {
  const _ReviewListPane();

  @override
  ConsumerState<_ReviewListPane> createState() => _ReviewListPaneState();
}

class _ReviewListPaneState extends ConsumerState<_ReviewListPane> with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  String _filter = 'user';
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _page = 1;
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _page = 1;
    setState(() => _loading = true);
    try {
      final dio = ref.read(adminDioProvider);
      final resp = await dio.get('/admin/reviews', queryParameters: {
        if (_ctrl.text.isNotEmpty) 'q': _ctrl.text,
        'filter': _filter,
        'page': _page,
      });
      final data = resp.data as Map;
      setState(() {
        _total = data['total'] as int;
        _items = List<Map<String, dynamic>>.from(data['items']);
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _hide(int id, bool hide) async {
    try {
      final dio = ref.read(adminDioProvider);
      await dio.post('/admin/reviews/$id/${hide ? 'hide' : 'unhide'}');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('후기 삭제', style: TextStyle(fontSize: 15)),
        content: const Text('복구할 수 없습니다. 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final dio = ref.read(adminDioProvider);
      await dio.delete('/admin/reviews/$id');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      _ContentFilter(
        ctrl: _ctrl,
        filter: _filter,
        filters: const {'user': '일반', 'seed': 'AI 소개', 'hidden': '블라인드', 'all': '전체'},
        onFilter: (f) { _filter = f; _load(reset: true); },
        onSearch: () => _load(reset: true),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          Text('총 $_total건', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const Spacer(),
          if (_page > 1) TextButton(onPressed: () { _page--; _load(); }, child: const Text('이전', style: TextStyle(fontSize: 12))),
          if (_items.length == 30) TextButton(onPressed: () { _page++; _load(); }, child: const Text('다음', style: TextStyle(fontSize: 12))),
        ]),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: _items.length,
          itemBuilder: (_, i) {
            final r = _items[i];
            final isHidden = r['is_hidden'] as bool? ?? false;
            final isSeed = r['is_seed'] as bool? ?? false;
            return _ContentCard(
              title: '${r['academy_name']} · ★${r['rating']}',
              subtitle: isSeed ? 'AI 소개' : r['author_nickname'] as String? ?? '-',
              body: r['review_text'] as String? ?? '',
              timeAgo: _timeAgo(r['created_at'] as String?),
              isHidden: isHidden,
              reportCount: r['report_count'] as int? ?? 0,
              onHide: isSeed ? null : () => _hide(r['id'] as int, !isHidden),
              onDelete: () => _delete(r['id'] as int),
              badge: isSeed ? _statusChip('AI', Colors.purple) : null,
            );
          },
        ),
      ),
    ]);
  }
}

// ── 공통 콘텐츠 카드 / 필터 ────────────────────────────

class _ContentFilter extends StatelessWidget {
  final TextEditingController ctrl;
  final String filter;
  final Map<String, String> filters;
  final void Function(String) onFilter;
  final VoidCallback onSearch;

  const _ContentFilter({
    required this.ctrl,
    required this.filter,
    required this.filters,
    required this.onFilter,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: '내용 검색',
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: IconButton(icon: const Icon(Icons.send, size: 16), onPressed: onSearch),
          ),
          onSubmitted: (_) => onSearch(),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        child: Row(
          children: filters.entries.map((e) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(e.value, style: const TextStyle(fontSize: 12)),
              selected: filter == e.key,
              onSelected: (_) => onFilter(e.key),
              visualDensity: VisualDensity.compact,
            ),
          )).toList(),
        ),
      ),
    ]);
  }
}

class _ContentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String body;
  final String timeAgo;
  final bool isHidden;
  final int reportCount;
  final VoidCallback? onHide;
  final VoidCallback onDelete;
  final Widget? badge;

  const _ContentCard({
    required this.title,
    required this.subtitle,
    required this.body,
    required this.timeAgo,
    required this.isHidden,
    required this.reportCount,
    required this.onHide,
    required this.onDelete,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (badge != null) ...[const SizedBox(width: 4), badge!],
            if (isHidden) ...[const SizedBox(width: 4), _statusChip('블라인드', Colors.orange)],
            if (reportCount > 0) ...[const SizedBox(width: 4), _statusChip('신고 $reportCount', Colors.red)],
          ]),
          Text('$subtitle · $timeAgo', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(body, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.3)),
          ],
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (onHide != null)
              TextButton(
                onPressed: onHide,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  foregroundColor: isHidden ? Colors.green : Colors.orange,
                ),
                child: Text(isHidden ? '표시' : '블라인드', style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: onDelete,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                foregroundColor: Colors.red,
              ),
              child: const Text('삭제', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── 5. 설정 탭 ────────────────────────────────────────

class _SettingsTab extends ConsumerStatefulWidget {
  const _SettingsTab();

  @override
  ConsumerState<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<_SettingsTab> with SingleTickerProviderStateMixin {
  late final TabController _tc = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabBar(
        controller: _tc,
        labelStyle: const TextStyle(fontSize: 12),
        tabs: const [Tab(text: '공지 작성'), Tab(text: '금칙어'), Tab(text: '관리 로그')],
      ),
      Expanded(
        child: TabBarView(
          controller: _tc,
          children: const [_NoticePane(), _ProfanityPane(), _LogPane()],
        ),
      ),
    ]);
  }
}

// ── 공지 작성 ─────────────────────────────────────────

class _NoticePane extends ConsumerStatefulWidget {
  const _NoticePane();

  @override
  ConsumerState<_NoticePane> createState() => _NoticePaneState();
}

class _NoticePaneState extends ConsumerState<_NoticePane> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _schoolSearchCtrl = TextEditingController();
  String _boardType = 'notice';
  String? _targetRegion;
  String? _targetSchoolCode;
  String? _targetSchoolName;
  List<Map<String, dynamic>> _schoolResults = [];
  bool _schoolSearching = false;
  bool _pinned = false;
  bool _saving = false;

  static const _regions = [
    '강남구','강동구','강북구','강서구','관악구','광진구','구로구','금천구',
    '노원구','도봉구','동대문구','동작구','마포구','서대문구','서초구','성동구',
    '성북구','송파구','양천구','영등포구','용산구','은평구','종로구','중구','중랑구',
    '수원시','성남시','용인시','안양시','부천시','광명시','안산시','고양시','의정부시',
    '기타',
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _schoolSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchSchool() async {
    final q = _schoolSearchCtrl.text.trim();
    if (q.length < 2) return;
    setState(() { _schoolSearching = true; _schoolResults = []; });
    try {
      final dio = ref.read(adminDioProvider);
      final resp = await dio.get('/schools/search', queryParameters: {'q': q});
      setState(() => _schoolResults = List<Map<String, dynamic>>.from(resp.data as List));
    } catch (_) {} finally {
      if (mounted) setState(() => _schoolSearching = false);
    }
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.isEmpty || _contentCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('제목과 내용을 입력해주세요.')));
      return;
    }
    if (_boardType == 'region' && _targetRegion == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지역을 선택해주세요.')));
      return;
    }
    if (_boardType == 'school' && _targetSchoolCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('학교를 선택해주세요.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = ref.read(adminDioProvider);
      final body = <String, dynamic>{
        'title': _titleCtrl.text,
        'content': _contentCtrl.text,
        'board_type': _boardType,
        'is_pinned': _pinned,
      };
      if (_boardType == 'region' && _targetRegion != null) body['target_region'] = _targetRegion;
      if (_boardType == 'school' && _targetSchoolCode != null) body['target_school_code'] = _targetSchoolCode;
      await dio.post('/posts', data: body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('공지 작성 완료')));
        _titleCtrl.clear();
        _contentCtrl.clear();
        _schoolSearchCtrl.clear();
        setState(() { _pinned = false; _targetRegion = null; _targetSchoolCode = null; _targetSchoolName = null; _schoolResults = []; });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          value: _boardType,
          decoration: const InputDecoration(
            labelText: '게시판', border: OutlineInputBorder(), isDense: true),
          items: const [
            DropdownMenuItem(value: 'notice', child: Text('공지사항')),
            DropdownMenuItem(value: 'free', child: Text('전체')),
            DropdownMenuItem(value: 'region', child: Text('지역')),
            DropdownMenuItem(value: 'school', child: Text('학교')),
          ],
          onChanged: (v) => setState(() {
            _boardType = v!;
            _targetRegion = null;
            _targetSchoolCode = null;
            _targetSchoolName = null;
            _schoolResults = [];
            _schoolSearchCtrl.clear();
          }),
        ),
        // 지역 선택 (region 게시판)
        if (_boardType == 'region') ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _targetRegion,
            decoration: const InputDecoration(
              labelText: '타겟 지역', border: OutlineInputBorder(), isDense: true),
            hint: const Text('지역 선택'),
            items: _regions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
            onChanged: (v) => setState(() => _targetRegion = v),
          ),
        ],
        // 학교 검색 (school 게시판)
        if (_boardType == 'school') ...[
          const SizedBox(height: 10),
          if (_targetSchoolName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Expanded(child: Text('선택됨: $_targetSchoolName',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary))),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() { _targetSchoolCode = null; _targetSchoolName = null; }),
                  visualDensity: VisualDensity.compact,
                ),
              ]),
            )
          else ...[
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _schoolSearchCtrl,
                  decoration: const InputDecoration(
                    labelText: '학교명 검색', border: OutlineInputBorder(), isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18)),
                  onSubmitted: (_) => _searchSchool(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _schoolSearching ? null : _searchSchool,
                child: _schoolSearching
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('검색'),
              ),
            ]),
            if (_schoolResults.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _schoolResults.length,
                  itemBuilder: (_, i) {
                    final s = _schoolResults[i];
                    return ListTile(
                      dense: true,
                      title: Text(s['school_name'] as String? ?? ''),
                      subtitle: Text(s['address'] as String? ?? '', style: const TextStyle(fontSize: 11)),
                      onTap: () => setState(() {
                        _targetSchoolCode = s['school_code'] as String?;
                        _targetSchoolName = s['school_name'] as String?;
                        _schoolResults = [];
                        _schoolSearchCtrl.clear();
                      }),
                    );
                  },
                ),
              ),
          ],
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(
            labelText: '제목', border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _contentCtrl,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: '내용', border: OutlineInputBorder(),
            alignLabelWithHint: true),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          title: const Text('상단 고정', style: TextStyle(fontSize: 13)),
          value: _pinned,
          onChanged: (v) => setState(() => _pinned = v!),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(height: 18, width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('공지 작성'),
        ),
      ]),
    );
  }
}

// ── 금칙어 관리 ────────────────────────────────────────

class _ProfanityPane extends ConsumerStatefulWidget {
  const _ProfanityPane();

  @override
  ConsumerState<_ProfanityPane> createState() => _ProfanityPaneState();
}

class _ProfanityPaneState extends ConsumerState<_ProfanityPane> with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _words = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(adminDioProvider);
      final resp = await dio.get('/admin/profanity');
      setState(() => _words = List<Map<String, dynamic>>.from(resp.data));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final word = _ctrl.text.trim();
    if (word.isEmpty) return;
    try {
      final dio = ref.read(adminDioProvider);
      await dio.post('/admin/profanity', data: {'word': word});
      _ctrl.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  Future<void> _delete(int id) async {
    try {
      final dio = ref.read(adminDioProvider);
      await dio.delete('/admin/profanity/$id');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                hintText: '금칙어 입력', border: OutlineInputBorder(), isDense: true),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _add, child: const Text('추가')),
        ]),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: _words.isEmpty && !_loading
            ? const Center(child: Text('등록된 금칙어가 없습니다.', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                itemCount: _words.length,
                itemBuilder: (_, i) {
                  final w = _words[i];
                  return ListTile(
                    dense: true,
                    title: Text(w['word'] as String, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(_timeAgo(w['created_at'] as String?),
                        style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      onPressed: () => _delete(w['id'] as int),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

// ── 관리 로그 ─────────────────────────────────────────

class _LogPane extends ConsumerStatefulWidget {
  const _LogPane();

  @override
  ConsumerState<_LogPane> createState() => _LogPaneState();
}

class _LogPaneState extends ConsumerState<_LogPane> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _logs = [];
  int _total = 0;
  int _page = 1;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(adminDioProvider);
      final resp = await dio.get('/admin/logs', queryParameters: {'page': _page});
      final data = resp.data as Map;
      setState(() {
        _total = data['total'] as int;
        _logs = List<Map<String, dynamic>>.from(data['items']);
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  static final _actionColors = <String, Color>{
    'approve': Colors.green,
    'reject': Colors.red,
    'ban': Colors.red,
    'suspend': Colors.orange,
    'warn': Colors.orange,
    'hide': Colors.orange,
    'unhide': Colors.green,
    'delete': Colors.red,
    'add': Colors.blue,
  };

  Color _actionColor(String type) {
    for (final entry in _actionColors.entries) {
      if (type.contains(entry.key)) return entry.value;
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          Text('총 $_total건', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const Spacer(),
          if (_page > 1) TextButton(
            onPressed: () { _page--; _load(); },
            child: const Text('이전', style: TextStyle(fontSize: 12)),
          ),
          if (_logs.length == 50) TextButton(
            onPressed: () { _page++; _load(); },
            child: const Text('다음', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: ListView.builder(
          itemCount: _logs.length,
          itemBuilder: (_, i) {
            final log = _logs[i];
            final type = log['action_type'] as String;
            return ListTile(
              dense: true,
              leading: Container(
                width: 6,
                height: 30,
                decoration: BoxDecoration(
                  color: _actionColor(type),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              title: Row(children: [
                Text(type, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _actionColor(type))),
                if ((log['target_type'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text('· ${log['target_type']} #${log['target_id']}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ]),
              subtitle: Text(
                '${log['admin_nickname']} · ${_timeAgo(log['created_at'] as String?)}${(log['detail'] as String? ?? '').isNotEmpty ? ' · ${(log['detail'] as String).substring(0, (log['detail'] as String).length.clamp(0, 40))}' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ── 공통 헬퍼 ─────────────────────────────────────────

Widget _errWidget(VoidCallback retry) => Center(
  child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline, color: Colors.grey, size: 40),
    const SizedBox(height: 8),
    const Text('데이터를 불러오지 못했습니다.', style: TextStyle(color: Colors.grey)),
    const SizedBox(height: 12),
    FilledButton(onPressed: retry, child: const Text('다시 시도')),
  ]),
);
