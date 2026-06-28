import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/api_client.dart' show tokenStorageProvider;
import '../../../core/constants.dart';
import '../admin_api.dart';

class AdminHomeScreen extends ConsumerStatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  ConsumerState<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends ConsumerState<AdminHomeScreen> {
  int _tab = 0;

  Future<void> _logout() async {
    await ref.read(tokenStorageProvider).deleteAll();
    if (mounted) context.go('/auth/login');
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ['대시보드', '캡처 심사', '신고 처리', '유저 관리', '공지 작성'];
    return Scaffold(
      appBar: AppBar(
        title: Text(tabs[_tab], style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: const Icon(Icons.admin_panel_settings, color: Color(0xFF4A90D9)),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout, tooltip: '로그아웃'),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          _DashboardTab(),
          _CapturesTab(),
          _ReportsTab(),
          _UsersTab(),
          _PostWriteTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: '대시보드'),
          NavigationDestination(icon: Icon(Icons.pending_actions_outlined), selectedIcon: Icon(Icons.pending_actions), label: '캡처심사'),
          NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag), label: '신고'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: '유저'),
          NavigationDestination(icon: Icon(Icons.edit_outlined), selectedIcon: Icon(Icons.edit), label: '공지'),
        ],
      ),
    );
  }
}

// ── 대시보드 ────────────────────────────────────────────────────

class _DashboardTab extends ConsumerStatefulWidget {
  const _DashboardTab();

  @override
  ConsumerState<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends ConsumerState<_DashboardTab> {
  Map<String, dynamic>? _stats;
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
      final results = await Future.wait([
        dio.get('/admin/users'),
        dio.get('/admin/captures'),
        dio.get('/admin/reports'),
      ]);
      final users = results[0].data as List;
      final captures = results[1].data as List;
      final reports = results[2].data as List;
      if (mounted) {
        setState(() {
          _stats = {
            'total_users': users.length,
            'members': users.where((u) => u['member_grade'] == 'member').length,
            'banned': users.where((u) => u['is_banned'] == true).length,
            'pending_captures': captures.length,
            'open_reports': reports.length,
          };
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final s = _stats ?? {};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatCard('전체 유저', '${s['total_users'] ?? 0}명', Icons.people, Colors.blue),
          _StatCard('정회원', '${s['members'] ?? 0}명', Icons.verified, Colors.green),
          _StatCard('캡처 심사 대기', '${s['pending_captures'] ?? 0}건', Icons.pending_actions, Colors.orange),
          _StatCard('미처리 신고', '${s['open_reports'] ?? 0}건', Icons.flag, Colors.red),
          _StatCard('영구 차단', '${s['banned'] ?? 0}명', Icons.block, Colors.grey),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.15), child: Icon(icon, color: color)),
        title: Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        trailing: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }
}

// ── 캡처 심사 ────────────────────────────────────────────────────

class _CapturesTab extends ConsumerStatefulWidget {
  const _CapturesTab();

  @override
  ConsumerState<_CapturesTab> createState() => _CapturesTabState();
}

class _CapturesTabState extends ConsumerState<_CapturesTab> {
  List<dynamic> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ref.read(adminDioProvider).get('/admin/captures');
      if (mounted) setState(() => _items = resp.data as List);
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(int id) async {
    try {
      await ref.read(adminDioProvider).post('/admin/captures/$id/approve');
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  Future<void> _reject(int id) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('거절 사유'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '사유 입력')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('거절')),
        ],
      ),
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await ref.read(adminDioProvider).post('/admin/captures/$id/reject', data: {'reason': reason});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return const Center(child: Text('심사 대기 없음'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final c = Map<String, dynamic>.from(_items[i] as Map);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${c['nickname']} — ${c['input_school_name']} ${c['input_grade']}학년',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('제출: ${c['created_at'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _approve(c['id'] as int),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('승인'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _reject(c['id'] as int),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('거절'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
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
}

// ── 신고 처리 ────────────────────────────────────────────────────

class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab();

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  List<dynamic> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ref.read(adminDioProvider).get('/admin/reports');
      if (mounted) setState(() => _items = resp.data as List);
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _action(int id, String action) async {
    try {
      await ref.read(adminDioProvider).post('/admin/reports/$id/review', data: {'action': action, 'reason': action});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return const Center(child: Text('미처리 신고 없음'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final r = Map<String, dynamic>.from(_items[i] as Map);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.flag, size: 16, color: Colors.red),
                  const SizedBox(width: 4),
                  Text('${r['target_type']} #${r['target_id']} — ${r['category']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ]),
                if (r['content_preview'] != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                    child: Text(r['content_preview'].toString().length > 100
                        ? '${r['content_preview'].toString().substring(0, 100)}...'
                        : r['content_preview'].toString(),
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 6, children: [
                  _ActionChip('경고', Colors.orange, () => _action(r['id'] as int, 'warn')),
                  _ActionChip('7일 정지', Colors.deepOrange, () => _action(r['id'] as int, 'suspend_7d')),
                  _ActionChip('30일 정지', Colors.red, () => _action(r['id'] as int, 'suspend_30d')),
                  _ActionChip('영구 차단', Colors.red.shade900, () => _action(r['id'] as int, 'ban')),
                  _ActionChip('기각', Colors.grey, () => _action(r['id'] as int, 'cleared')),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
      onPressed: onTap,
      side: BorderSide(color: color.withOpacity(0.5)),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ── 유저 관리 ────────────────────────────────────────────────────

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  List<dynamic> _items = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({String? q}) async {
    setState(() => _loading = true);
    try {
      final params = q != null && q.isNotEmpty ? {'q': q} : null;
      final resp = await ref.read(adminDioProvider).get('/admin/users', queryParameters: params);
      if (mounted) setState(() => _items = resp.data as List);
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _suspend(int id, int days) async {
    try {
      await ref.read(adminDioProvider).post('/admin/users/$id/suspend', data: {'days': days, 'reason': '관리자 제재'});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  Future<void> _ban(int id) async {
    try {
      await ref.read(adminDioProvider).post('/admin/users/$id/ban', data: {'reason': '관리자 영구 차단'});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  Future<void> _unban(int id) async {
    try {
      await ref.read(adminDioProvider).post('/admin/users/$id/unban');
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '닉네임 또는 ID 검색',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); _load(); }),
              isDense: true,
            ),
            onSubmitted: (q) => _load(q: q),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final u = Map<String, dynamic>.from(_items[i] as Map);
                    final isBanned = u['is_banned'] == true;
                    final grade = u['member_grade'] == 'member' ? '정회원' : '눈팅';
                    return Card(
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: isBanned ? Colors.red.shade100 : Colors.blue.shade50,
                          child: Icon(isBanned ? Icons.block : Icons.person,
                              color: isBanned ? Colors.red : Colors.blue, size: 18),
                        ),
                        title: Text(u['nickname'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text('$grade · 경고 ${u['warning_count'] ?? 0}회', style: const TextStyle(fontSize: 12)),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('학교: ${u['school_name'] ?? '-'} ${u['grade'] ?? ''}학년',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              const SizedBox(height: 8),
                              Wrap(spacing: 6, children: [
                                if (!isBanned) ...[
                                  _ActionChip('7일 정지', Colors.orange, () => _suspend(u['id'] as int, 7)),
                                  _ActionChip('30일 정지', Colors.deepOrange, () => _suspend(u['id'] as int, 30)),
                                  _ActionChip('영구 차단', Colors.red, () => _ban(u['id'] as int)),
                                ] else
                                  _ActionChip('차단 해제', Colors.green, () => _unban(u['id'] as int)),
                              ]),
                            ]),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── 공지 작성 ────────────────────────────────────────────────────

class _PostWriteTab extends ConsumerStatefulWidget {
  const _PostWriteTab();

  @override
  ConsumerState<_PostWriteTab> createState() => _PostWriteTabState();
}

class _PostWriteTabState extends ConsumerState<_PostWriteTab> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  String _boardType = 'free';
  bool _pinned = true;
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty || _contentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('제목과 내용을 입력해주세요.')));
      return;
    }
    setState(() => _loading = true);
    try {
      final userDio = Dio(BaseOptions(
        baseUrl: _PostWriteTabState._baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final adminToken = await readAdminToken();
      await userDio.post('/posts', data: {
        'board_type': _boardType,
        'title': _titleCtrl.text.trim(),
        'content': _contentCtrl.text.trim(),
        'is_anonymous': false,
        'is_pinned': _pinned,
      }, options: Options(headers: {'Authorization': 'Bearer $adminToken'}));
      if (mounted) {
        _titleCtrl.clear();
        _contentCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('게시글이 등록되었습니다!')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: ${e.response?.data ?? e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _baseUrl = String.fromEnvironment('BASE_URL', defaultValue: 'https://momstalk.onrender.com/api/v1');

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          value: _boardType,
          decoration: const InputDecoration(labelText: '게시판'),
          items: const [
            DropdownMenuItem(value: 'free', child: Text('전체 (공지)')),
            DropdownMenuItem(value: 'region', child: Text('지역')),
            DropdownMenuItem(value: 'school', child: Text('학교')),
            DropdownMenuItem(value: 'grade', child: Text('학년')),
          ],
          onChanged: (v) => setState(() => _boardType = v!),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(labelText: '제목'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _contentCtrl,
          maxLines: 10,
          decoration: const InputDecoration(labelText: '내용', alignLabelWithHint: true),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: _pinned,
          onChanged: (v) => setState(() => _pinned = v),
          title: const Text('상단 고정 (공지)'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('게시글 등록'),
        ),
      ]),
    );
  }
}
