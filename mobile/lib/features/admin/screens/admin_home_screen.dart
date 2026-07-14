import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/kst_time.dart';
import '../../../core/refresh_bus.dart';
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
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          // 탭을 다시 선택했을 때(같은 탭이든 다른 탭이든) 항상 최신 데이터를
          // 다시 불러오도록 신호를 보낸다. AutomaticKeepAliveClientMixin으로
          // 탭 전환 시 State는 유지되지만, 그 사이 다른 경로로 데이터가 바뀌었을
          // 수 있으므로 탭 선택은 곧 새로고침 요청으로 취급한다.
          bumpAdminRefresh(ref);
        },
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
    ref.listen<int>(adminRefreshSignal, (prev, next) {
      if (prev != null && prev != next) _load();
    });
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

          // 사용자 현황 (한 줄에 6개 — 카드 폭을 절반으로 줄여 더 압축)
          _SectionTitle('사용자'),
          _StatGrid([
            _StatItem('전체', '${users['total']}명', Icons.people, Colors.blue),
            _StatItem('정회원', '${users['member']}명', Icons.verified_user, Colors.green),
            _StatItem('눈팅', '${users['lurker']}명', Icons.visibility_off, Colors.grey),
            _StatItem('오늘 가입', '+${users['new_today']}명', Icons.person_add, Colors.teal),
            _StatItem('이번주', '+${users['new_week']}명', Icons.calendar_today, Colors.indigo),
            _StatItem('정지/차단', '${(users['suspended'] as int) + (users['banned'] as int)}명', Icons.block, Colors.red),
          ], crossAxisCount: 6, aspectRatio: 1.3),
          const SizedBox(height: 8),

          // 게시글 + 학원 후기 현황 (한 그리드로 압축)
          _SectionTitle('게시글 · 학원 후기'),
          _StatGrid([
            _StatItem('게시글 전체', '${posts['total']}건', Icons.article, Colors.purple),
            _StatItem('오늘', '+${posts['today']}건', Icons.today, Colors.deepPurple),
            _StatItem('이번주', '+${posts['week']}건', Icons.calendar_month, Colors.purple.shade300),
            _StatItem('블라인드', '${posts['hidden']}건', Icons.hide_source, Colors.orange),
            _StatItem('후기 전체', '${reviews['total']}건', Icons.rate_review, Colors.cyan),
            _StatItem('후기 블라인드', '${reviews['hidden']}건', Icons.hide_source, Colors.orange),
          ], crossAxisCount: 6, aspectRatio: 1.3),
          const SizedBox(height: 8),

          // 7일 가입·게시글 작성 추이 — 가입 추이만으로는 "가입은 했는데
          // 활동은 하는지"를 알 수 없어서, 같은 날짜 축에 게시글 작성 추이도
          // 막대로 함께 표시해 온보딩 이후 이탈 여부를 한눈에 비교할 수 있게 함.
          _SectionTitle('최근 7일 가입·게시글 작성 추이'),
          _GroupedDailyChart(
            daily1: List<Map<String, dynamic>>.from(_data!['daily_signup'] ?? []),
            daily2: List<Map<String, dynamic>>.from(_data!['daily_posts'] ?? []),
            label1: '가입',
            label2: '게시글',
            color1: const Color(0xFF4A90D9),
            color2: Colors.deepPurple,
          ),
          const SizedBox(height: 8),

          // 학교별 가입 인원 (학교 게시판 언락 화면과 동일 기준)
          _SectionTitle('학교별 가입 인원 (정회원 기준, 상위 10곳)'),
          _SchoolBarChart(bySchool: List<Map<String, dynamic>>.from(_data!['by_school'] ?? [])),
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
  final double aspectRatio;
  final int crossAxisCount;
  const _StatGrid(this.items, {this.aspectRatio = 2.0, this.crossAxisCount = 3});

  @override
  Widget build(BuildContext context) {
    // 카드 폭이 좁아질수록(칼럼 수가 많을수록) 아이콘/글자 크기를 줄여서
    // 라벨이 잘리거나 줄바꿈되지 않도록 한다.
    final compact = crossAxisCount >= 5;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: compact ? 6 : 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (_, i) {
        final item = items[i];
        return Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 6 : 8),
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
                Icon(item.icon, size: compact ? 11 : 13, color: item.color),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(item.label,
                      style: TextStyle(fontSize: compact ? 9 : 10, color: item.color.withOpacity(0.8)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 2),
              Text(item.value,
                  style: TextStyle(fontSize: compact ? 12 : 14, fontWeight: FontWeight.bold, color: item.color),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      },
    );
  }
}

class _GroupedDailyChart extends StatelessWidget {
  final List<Map<String, dynamic>> daily1;
  final List<Map<String, dynamic>> daily2;
  final String label1;
  final String label2;
  final Color color1;
  final Color color2;
  const _GroupedDailyChart({
    required this.daily1,
    required this.daily2,
    required this.label1,
    required this.label2,
    required this.color1,
    required this.color2,
  });

  @override
  Widget build(BuildContext context) {
    if (daily1.isEmpty && daily2.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('데이터 없음', style: TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }
    final counts1 = {for (final d in daily1) d['date'] as String: d['count'] as int};
    final counts2 = {for (final d in daily2) d['date'] as String: d['count'] as int};
    final dates = {...counts1.keys, ...counts2.keys}.toList()..sort();
    final maxVal = [...counts1.values, ...counts2.values, 1].reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: [
        // 범례
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _legendDot(color1, label1),
          const SizedBox(width: 14),
          _legendDot(color2, label2),
        ]),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: dates.map((date) {
            final c1 = counts1[date] ?? 0;
            final c2 = counts2[date] ?? 0;
            final ratio1 = maxVal > 0 ? c1 / maxVal : 0.0;
            final ratio2 = maxVal > 0 ? c2 / maxVal : 0.0;
            final dateStr = date.substring(5); // MM-DD
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$c1', style: const TextStyle(fontSize: 8, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Container(
                        width: 10,
                        height: 60 * ratio1 + 3,
                        decoration: BoxDecoration(color: color1.withOpacity(0.75), borderRadius: BorderRadius.circular(2)),
                      ),
                    ]),
                    const SizedBox(width: 3),
                    Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('$c2', style: const TextStyle(fontSize: 8, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Container(
                        width: 10,
                        height: 60 * ratio2 + 3,
                        decoration: BoxDecoration(color: color2.withOpacity(0.75), borderRadius: BorderRadius.circular(2)),
                      ),
                    ]),
                  ]),
                  const SizedBox(height: 4),
                  Text(dateStr, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                ]),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }
}

class _SchoolBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> bySchool;
  const _SchoolBarChart({required this.bySchool});

  @override
  Widget build(BuildContext context) {
    if (bySchool.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Text('아직 학교별 가입자 데이터가 없습니다.', style: TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }
    final maxVal = bySchool.map((s) => s['member_count'] as int).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: bySchool.map((s) {
          final name = s['school_name'] as String? ?? '-';
          final cnt = s['member_count'] as int;
          final ratio = maxVal > 0 ? cnt / maxVal : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(
                width: 92,
                child: Text(name, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                child: LayoutBuilder(builder: (ctx, constraints) {
                  return Stack(children: [
                    Container(height: 16, decoration: BoxDecoration(
                      color: Colors.grey.shade200, borderRadius: BorderRadius.circular(3))),
                    Container(
                      height: 16,
                      width: constraints.maxWidth * ratio.clamp(0.02, 1.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90D9),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ]);
                }),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 36,
                child: Text('$cnt명', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.right),
              ),
            ]),
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
  // 학교별 조회 모드 — 학교 게시판 언락 화면(UserChild.school_code +
  // member_grade='member' 기준)과 동일한 인원수를 그대로 보여준다. 예전에는
  // 관리자가 유저 목록에서 레거시 users.school_name 문구만 보고 눈대중으로
  // 세다 보니(다자녀·학교 변경 시 갱신 안 되는 필드) 언락 화면 숫자와 서로
  // 달라 보이는 문제가 있었다.
  Map<String, dynamic>? _schoolUnlock;
  String? _schoolName;
  List<Map<String, dynamic>> _schoolSiblings = [];

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
      if (_schoolUnlock != null) {
        final resp = await dio.get('/admin/schools/${_schoolUnlock!['school_code']}/members');
        final data = Map<String, dynamic>.from(resp.data);
        setState(() {
          _schoolUnlock = data;
          _users = List<Map<String, dynamic>>.from(data['users']);
        });
      } else {
        final resp = await dio.get('/admin/users', queryParameters: q.isNotEmpty ? {'q': q} : null);
        setState(() => _users = List<Map<String, dynamic>>.from(resp.data));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickSchool() async {
    final searchCtrl = TextEditingController();
    var results = <Map<String, dynamic>>[];
    var searching = false;
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          Future<void> search() async {
            final q = searchCtrl.text.trim();
            if (q.length < 2) return;
            setDialogState(() => searching = true);
            try {
              final dio = ref.read(adminDioProvider);
              final resp = await dio.get('/schools/search', queryParameters: {'q': q});
              results = List<Map<String, dynamic>>.from(resp.data as List);
            } catch (_) {}
            setDialogState(() => searching = false);
          }

          return AlertDialog(
            title: const Text('학교별 인원 조회', style: TextStyle(fontSize: 15)),
            content: SizedBox(
              width: 320,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        labelText: '학교명 검색', border: OutlineInputBorder(), isDense: true),
                      onSubmitted: (_) => search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: searching ? null : search,
                    child: searching
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('검색'),
                  ),
                ]),
                if (results.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    margin: const EdgeInsets.only(top: 8),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final s = results[i];
                        return ListTile(
                          dense: true,
                          title: Text(s['school_name'] as String? ?? ''),
                          subtitle: Text(s['address'] as String? ?? '', style: const TextStyle(fontSize: 11)),
                          onTap: () => Navigator.pop(dialogCtx, s),
                        );
                      },
                    ),
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('취소')),
            ],
          );
        },
      ),
    );
    if (picked == null) return;
    setState(() {
      _schoolUnlock = {'school_code': picked['school_code']};
      _schoolName = picked['school_name'] as String?;
      _schoolSiblings = [];
    });
    await _load('');
    await _checkNameDuplicates(picked['school_name'] as String? ?? '');
  }

  /// 같은 이름의 학교가 school_code만 다르게 여러 개 있으면(NEIS 데이터
  /// 특성상 지역별로 실제 존재), 유저 목록에서 이름만 보고 센 인원과
  /// 특정 코드 하나만 보는 이 화면의 인원이 서로 달라 보일 수 있다.
  Future<void> _checkNameDuplicates(String schoolName) async {
    if (schoolName.isEmpty) return;
    try {
      final dio = ref.read(adminDioProvider);
      final resp = await dio.get('/admin/schools/name-check', queryParameters: {'name': schoolName});
      final data = Map<String, dynamic>.from(resp.data as Map);
      final schools = List<Map<String, dynamic>>.from(data['schools'] as List);
      if (mounted) setState(() => _schoolSiblings = schools);
    } catch (_) {}
  }

  void _clearSchoolMode() {
    setState(() {
      _schoolUnlock = null;
      _schoolName = null;
      _schoolSiblings = [];
    });
    _load(_ctrl.text);
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
    ref.listen<int>(adminRefreshSignal, (prev, next) {
      if (prev != null && prev != next) _load(_ctrl.text);
    });
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              enabled: _schoolUnlock == null,
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
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.school_outlined, size: 20),
            tooltip: '학교별 인원 조회 (학교 게시판 언락 화면과 동일 기준)',
            onPressed: _pickSchool,
          ),
        ]),
      ),
      if (_schoolUnlock != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                  '$_schoolName · 정회원 ${_schoolUnlock!['member_count']}/${_schoolUnlock!['threshold']}명'
                  '${(_schoolUnlock!['unlocked'] as bool? ?? false) ? ' (언락됨)' : ''}'
                  ' · 전체 가입(인증대기 포함) ${_schoolUnlock!['total_registered'] ?? '-'}명'
                  '\n학교 게시판 언락/대시보드는 "정회원"만 세요 — 인증 전 계정까지 세면 문턱 의미가 없어져요.',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: _clearSchoolMode,
              ),
            ]),
          ),
        ),
      if (_schoolSiblings.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('⚠️ 같은 이름의 학교가 ${_schoolSiblings.length}개(코드가 다름) 등록돼 있어요 — '
                  '유저 목록에서 "$_schoolName"으로 보이는 인원은 아래 전체를 합친 숫자일 수 있어요.',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ..._schoolSiblings.map((s) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '· ${s['school_code']} (${s['address'] ?? s['region'] ?? '주소 미상'}) — '
                  '정회원 ${s['member_count']}명 · 전체 가입 ${s['total_registered']}명',
                  style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                ),
              )),
            ]),
          ),
        ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      if (_schoolUnlock == null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Text(
            _ctrl.text.isEmpty ? '총 ${_users.length}명 (최근 가입순, 최대 100명 표시)' : '검색 결과 ${_users.length}명',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
          ),
        ),
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

  /// 등록된 모든 자녀의 학교를 보여준다. users.school_name(레거시, 첫 자녀
  /// 등록 시에만 동기화)만 보면 다자녀·학교 변경 계정에서 실제와 달라 보이는
  /// 문제가 있어, GET /admin/users가 내려주는 children 배열을 우선 사용한다.
  String _schoolsLabel(Map<String, dynamic> user) {
    final children = (user['children'] as List?)?.cast<Map>() ?? [];
    if (children.isEmpty) return (user['school_name'] as String?) ?? '-';
    return children.map((c) {
      final name = c['school_name'] as String? ?? '-';
      final grade = c['grade'] as int?;
      final active = c['is_active'] == true;
      final label = grade != null ? '$name($grade학년)' : name;
      return children.length > 1 && active ? '$label★' : label;
    }).join(', ');
  }

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
            '${_schoolsLabel(user)} · 가입 ${_timeAgo(user['created_at'] as String?)}'
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
    ref.listen<int>(adminRefreshSignal, (prev, next) {
      if (prev != null && prev != next) _load();
    });
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return const Center(child: Text('대기 중인 캡처가 없습니다.', style: TextStyle(color: Colors.grey)));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: _items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          if (i == 0) {
            return Text('심사 대기 총 ${_items.length}건',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600));
          }
          final c = _items[i - 1];
          return _buildCaptureCard(c);
        },
      ),
    );
  }

  Widget _buildCaptureCard(Map<String, dynamic> c) {
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
            if (c['input_school_type'] == 'preschool') ...[
              const SizedBox(width: 6),
              _statusChip('미취학', Colors.orange),
            ],
            const Spacer(),
            Text(_timeAgo(c['created_at'] as String?),
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
          const SizedBox(height: 4),
          Text(
            c['input_school_type'] == 'preschool'
                ? '미취학 · ${c['input_region'] ?? '-'}'
                : '${c['input_school_name']} · ${c['input_grade']}학년${c['input_class_num'] != null ? ' ${c['input_class_num']}반' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
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
    ref.listen<int>(adminRefreshSignal, (prev, next) {
      if (prev != null && prev != next) _load();
    });
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
      // 관리자 화면 자체는 새로고침되지만, 이 신호가 없으면 이미 열려있는
      // 사용자 게시판 탭(keep-alive로 상태 유지)은 블라인드 처리된 글이
      // 그대로 보이는 등 계속 예전 목록을 보여줬다.
      bumpBoardRefresh(ref);
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
      bumpBoardRefresh(ref);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen<int>(adminRefreshSignal, (prev, next) {
      if (prev != null && prev != next) _load(reset: true);
    });
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
      bumpBoardRefresh(ref);
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
      bumpBoardRefresh(ref);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen<int>(adminRefreshSignal, (prev, next) {
      if (prev != null && prev != next) _load(reset: true);
    });
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
      bumpBoardRefresh(ref);
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
      bumpBoardRefresh(ref);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen<int>(adminRefreshSignal, (prev, next) {
      if (prev != null && prev != next) _load(reset: true);
    });
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
  // 공지는 항상 board_type='notice'로 저장되고(post_service.list_posts가
  // 게시판별로 알아서 상단에 고정해줌), 이 값은 어느 범위에 노출할지만
  // 결정한다. 예전엔 이 값을 그대로 board_type으로 보내서 "지역" 선택 시
  // 실제로는 board_type='region'인 평범한 게시글이 만들어졌고, 그 결과
  // 공지 고정이 전혀 동작하지 않고 인기글에 밀려 보이는 버그가 있었다.
  String _scope = 'global';
  String? _targetRegion;
  String? _targetSchoolCode;
  String? _targetSchoolName;
  List<Map<String, dynamic>> _schoolResults = [];
  bool _schoolSearching = false;
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
    if (_scope == 'region' && _targetRegion == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지역을 선택해주세요.')));
      return;
    }
    if (_scope == 'school' && _targetSchoolCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('학교를 선택해주세요.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = ref.read(adminDioProvider);
      final body = <String, dynamic>{
        'title': _titleCtrl.text,
        'content': _contentCtrl.text,
        'board_type': 'notice',
      };
      if (_scope == 'region' && _targetRegion != null) body['target_region'] = _targetRegion;
      if (_scope == 'school' && _targetSchoolCode != null) body['target_school_code'] = _targetSchoolCode;
      await dio.post('/posts', data: body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('공지 작성 완료')));
        _titleCtrl.clear();
        _contentCtrl.clear();
        _schoolSearchCtrl.clear();
        setState(() { _targetRegion = null; _targetSchoolCode = null; _targetSchoolName = null; _schoolResults = []; });
        // 이게 없으면 이미 열려있는 게시판 탭(keep-alive)에는 방금 쓴 공지가
        // 최상단 고정으로 바로 안 뜨고 새로고침해야만 보였다.
        bumpBoardRefresh(ref);
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
          value: _scope,
          decoration: const InputDecoration(
            labelText: '노출 범위', border: OutlineInputBorder(), isDense: true),
          items: const [
            DropdownMenuItem(value: 'global', child: Text('전체 게시판')),
            DropdownMenuItem(value: 'region', child: Text('특정 지역 게시판')),
            DropdownMenuItem(value: 'school', child: Text('특정 학교 게시판')),
          ],
          onChanged: (v) => setState(() {
            _scope = v!;
            _targetRegion = null;
            _targetSchoolCode = null;
            _targetSchoolName = null;
            _schoolResults = [];
            _schoolSearchCtrl.clear();
          }),
        ),
        // 지역 선택
        if (_scope == 'region') ...[
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
        // 학교 검색
        if (_scope == 'school') ...[
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
        const SizedBox(height: 4),
        Text('작성한 공지는 해당 범위의 게시판 상단에 자동으로 고정돼요.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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

class _PresetSetTile extends StatelessWidget {
  final String title;
  final List<String> words;
  final VoidCallback onCopy;
  const _PresetSetTile({required this.title, required this.words, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
            TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('복사', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ]),
          Text(words.join(', '), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
      ),
    );
  }
}

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

  Future<void> _bulkAdd() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('금칙어 일괄 추가'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('쉼표(,)로 구분해서 여러 단어를 한 번에 붙여넣으세요.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '예: 시발, 개새끼, 병신',
                border: OutlineInputBorder(),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('일괄 추가')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      final dio = ref.read(adminDioProvider);
      final resp = await dio.post('/admin/profanity/bulk', data: {'words': text});
      final added = resp.data['added'] as int? ?? 0;
      final skipped = resp.data['skipped'] as int? ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$added개 추가됨' + (skipped > 0 ? ' · $skipped개는 이미 등록되어 건너뜀' : ''))),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('일괄 추가 실패: $e')));
    }
  }

  void _showPresetSets() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('금칙어 세트'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('아래에서 복사한 뒤 "일괄 추가" 창에 붙여넣으세요.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              ..._profanityPresets.entries.map((e) => _PresetSetTile(
                    title: e.key,
                    words: e.value,
                    onCopy: () async {
                      await Clipboard.setData(ClipboardData(text: e.value.join(', ')));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('"${e.key}" 세트가 복사되었습니다.')),
                        );
                      }
                    },
                  )),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
        ],
      ),
    );
  }

  // 이미 core/profanity.py의 기본 목록(_DEFAULT_WORDS)이 코드 레벨에서 항상
  // 적용되므로, 여기서는 그것과 겹치지 않는 추가 세트만 제공한다 — 커뮤니티
  // 특성상 자주 문제되는 표현/은어/우회 변형 위주.
  static const Map<String, List<String>> _profanityPresets = {
    '자녀·가족 비하': [
      '급식충', '유치원충', '초딩충', '개저씨', '노키즈존', '맘충', '전업맘 무시',
    ],
    '외모·비교 비하': [
      '못생김', '뚱뚱해서', '살쪄서', '거지같이', '싼티', '없어보임',
    ],
    '광고·스팸성 표현': [
      '무료체험', '지금클릭', '최저가보장', '카톡문의', '텔레그램문의', '부업추천',
    ],
    '자음/변형 우회 욕설': [
      'ㅗㅗ', 'ㅄㅅㄲ', 'ㅁㄴㅆㄲ', 'ㅅㄲㄲ', 'fuckyou', 'stfu',
    ],
  };

  Future<void> _edit(int id, String currentWord) async {
    final ctrl = TextEditingController(text: currentWord);
    final newWord = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('금칙어 수정'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '금칙어', border: OutlineInputBorder(), isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('저장')),
        ],
      ),
    );
    if (newWord == null || newWord.isEmpty || newWord == currentWord) return;
    try {
      final dio = ref.read(adminDioProvider);
      await dio.patch('/admin/profanity/$id', data: {'word': newWord});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('수정되었습니다.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('수정 실패: $e')));
    }
  }

  Future<void> _delete(int id, String word) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('금칙어 삭제'),
        content: Text('"$word"를 금칙어 목록에서 삭제할까요?'),
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
    if (confirmed != true) return;
    try {
      final dio = ref.read(adminDioProvider);
      await dio.delete('/admin/profanity/$id');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제되었습니다.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen<int>(adminRefreshSignal, (prev, next) {
      if (prev != null && prev != next) _load();
    });
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        // Row + Expanded 조합 대신 세로로 쌓아, 폭 제약이 애매한 상황에서도
        // 항상 버튼이 화면에 그려지도록 함(가로 배치에서 버튼이 아예 안
        // 보인다는 리포트가 있었음).
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              hintText: '금칙어 입력', border: OutlineInputBorder(), isDense: true),
            onSubmitted: (_) => _add(),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _add, child: const Text('금칙어 추가')),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _bulkAdd,
                icon: const Icon(Icons.playlist_add, size: 16),
                label: const Text('일괄 추가 (쉼표 구분)', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _showPresetSets,
                icon: const Icon(Icons.content_copy, size: 16),
                label: const Text('금칙어 세트', style: TextStyle(fontSize: 12)),
              ),
            ),
          ]),
        ]),
      ),
      if (_loading) const LinearProgressIndicator(minHeight: 2),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Text('총 ${_words.length}개', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
      ),
      Expanded(
        child: _words.isEmpty && !_loading
            ? const Center(child: Text('등록된 금칙어가 없습니다.', style: TextStyle(color: Colors.grey)))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                // 한 줄에 하나씩 나열되던 리스트를, 여러 개가 한 줄에 배치되는
                // 버튼(칩) 형태로 바꿔 한눈에 훑어보기 쉽게 함.
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _words.map((w) {
                    final id = w['id'] as int;
                    final word = w['word'] as String;
                    return InputChip(
                      label: Text(word, style: const TextStyle(fontSize: 12)),
                      onPressed: () => _edit(id, word),
                      onDeleted: () => _delete(id, word),
                      deleteIconColor: Colors.red.shade300,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
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

  // action_type은 서버가 영문 snake_case로 기록한다(approve_user,
  // suspend_7d, report_warn 등). 그대로 보여주면 무슨 처리인지 알아보기
  // 어렵다는 피드백을 받아 한국어 설명 문구로 변환한다. 정확히 일치하는
  // 값을 먼저 찾고, suspend_7d/suspend_30d처럼 접미사가 붙는 값은 접두어
  // 매칭으로 처리한다.
  static const _exactLabels = <String, String>{
    'approve_user': '유저 수동 승인 (정회원 승급)',
    'approve_capture': '가입 인증 캡처 승인',
    'reject_capture': '가입 인증 캡처 반려',
    'warn': '경고 부여',
    'ban': '영구 정지',
    'unban': '정지 해제',
    'grant_trust': '인증 면제 권한 부여',
    'revoke_trust': '인증 면제 권한 회수',
    'hide_post': '게시글 블라인드 처리',
    'unhide_post': '게시글 블라인드 해제',
    'delete_post': '게시글 삭제',
    'hide_comment': '댓글 블라인드 처리',
    'unhide_comment': '댓글 블라인드 해제',
    'delete_comment': '댓글 삭제',
    'hide_review': '후기 블라인드 처리',
    'unhide_review': '후기 블라인드 해제',
    'delete_review': '후기 삭제',
    'add_profanity': '금칙어 추가',
    'add_profanity_bulk': '금칙어 일괄 추가',
    'edit_profanity': '금칙어 수정',
    'delete_profanity': '금칙어 삭제',
    'report_warn': '신고 처리 — 경고',
    'report_suspend_7d': '신고 처리 — 7일 정지',
    'report_suspend_30d': '신고 처리 — 30일 정지',
    'report_ban': '신고 처리 — 영구 정지',
    'report_cleared': '신고 처리 — 조치 없음(기각)',
  };

  static const _targetLabels = <String, String>{
    'user': '유저',
    'post': '게시글',
    'comment': '댓글',
    'review': '학원 후기',
    'capture': '인증 캡처',
    'report': '신고',
  };

  String _actionLabel(String type) {
    if (_exactLabels.containsKey(type)) return _exactLabels[type]!;
    if (type.startsWith('suspend_')) {
      final days = type.substring('suspend_'.length).replaceAll('d', '');
      return '$days일 정지';
    }
    return type; // 매핑에 없는 새 action_type은 원문 그대로 표시 (누락 방지)
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen<int>(adminRefreshSignal, (prev, next) {
      if (prev != null && prev != next) _load();
    });
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
        child: ListView.separated(
          itemCount: _logs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final log = _logs[i];
            final type = log['action_type'] as String;
            final targetType = log['target_type'] as String? ?? '';
            final detail = log['detail'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(color: _actionColor(type), borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_actionLabel(type),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _actionColor(type))),
                      const SizedBox(height: 2),
                      Text(
                        '${log['admin_nickname'] ?? '관리자'} 처리 · ${_timeAgo(log['created_at'] as String?)}'
                        '${targetType.isNotEmpty ? ' · 대상: ${_targetLabels[targetType] ?? targetType} #${log['target_id']}' : ''}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('사유/내용: $detail', style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ]),
                  ),
                ]),
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
