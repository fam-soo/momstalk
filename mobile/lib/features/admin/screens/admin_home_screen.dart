import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
  final Map<int, Uint8List> _imageCache = {};
  final Map<int, String?> _imageFetchError = {};

  Future<Uint8List?> _fetchImage(int captureId) async {
    if (_imageCache.containsKey(captureId)) return _imageCache[captureId];
    try {
      final resp = await ref.read(adminDioProvider).get<List<int>>(
        '/admin/captures/$captureId/image',
        options: Options(responseType: ResponseType.bytes),
      );
      if (resp.data != null) {
        final bytes = Uint8List.fromList(resp.data!);
        _imageCache[captureId] = bytes;
        return bytes;
      }
    } on DioException catch (e) {
      final detail = (e.response?.data is Map)
          ? (e.response!.data as Map)['detail']?.toString()
          : null;
      _imageFetchError[captureId] = detail ?? 'HTTP ${e.response?.statusCode}';
    } catch (e) {
      _imageFetchError[captureId] = e.toString();
    }
    return null;
  }

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

  void _showImageDialog(BuildContext ctx, Uint8List bytes) {
    showDialog(
      context: ctx,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
          Positioned(
            top: 8, right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
            ),
          ),
        ]),
      ),
    );
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
          final captureId = c['id'] as int;
          final fallbackUrl = c['image_url'] as String?;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // 헤더
                Text('${c['nickname'] ?? '알 수 없음'} — ${c['input_school_name'] ?? ''} ${c['input_grade'] ?? ''}학년',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('제출: ${c['created_at'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 10),
                // 캡처 이미지 (백엔드 프록시로 S3 CORS 우회)
                FutureBuilder<Uint8List?>(
                  future: _fetchImage(captureId),
                  builder: (ctx2, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return Container(
                        height: 180,
                        color: Colors.grey.shade100,
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    final bytes = snap.data;
                    if (bytes == null) {
                      final errMsg = _imageFetchError[captureId];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200)),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.image_not_supported_outlined, color: Colors.orange.shade700, size: 28),
                          const SizedBox(height: 4),
                          Text(errMsg ?? '이미지 로드 실패',
                              style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                              textAlign: TextAlign.center),
                          if (fallbackUrl != null && !fallbackUrl.startsWith('/dev')) ...[
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: () => launchUrl(Uri.parse(fallbackUrl), mode: LaunchMode.externalApplication),
                              icon: const Icon(Icons.open_in_new, size: 14),
                              label: const Text('브라우저에서 열기', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            ),
                          ],
                        ]),
                      );
                    }
                    return GestureDetector(
                      onTap: () => _showImageDialog(ctx, bytes),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(bytes, height: 180, width: double.infinity, fit: BoxFit.cover),
                      ),
                    );
                  },
                ),
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

  Future<void> _approveUser(int id) async {
    try {
      await ref.read(adminDioProvider).post('/admin/users/$id/approve');
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('정회원으로 승인되었습니다.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
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
                          _UserDetailPanel(
                            userId: u['id'] as int,
                            summary: u,
                            onApprove: () => _approveUser(u['id'] as int),
                            onSuspend: (days) => _suspend(u['id'] as int, days),
                            onBan: () => _ban(u['id'] as int),
                            onUnban: () => _unban(u['id'] as int),
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
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  String _boardType = 'notice';

  static const _defaultTitle = 'MomsTalk 서비스 이용 안내 및 주요 기능 소개';
  static const _defaultContent = '''안녕하세요, MomsTalk 운영팀입니다 👋

MomsTalk는 학부모님들만의 안전하고 익명인 소통 공간입니다.
서비스 이용 전 아래 안내사항을 꼭 확인해 주세요.

━━━━━━━━━━━━━━━━━━━━━
📱 주요 기능 안내
━━━━━━━━━━━━━━━━━━━━━

🗺️ 지역 게시판
우리 동네 학부모님들과 지역 정보를 나눠보세요.
학원 정보, 지역 행사, 맛집 등 다양한 이야기를 나눌 수 있어요.

🏫 학교 게시판
우리 학교 학부모님들과만 소통하는 공간이에요.
학교 행사, 공지, 학년별 정보를 빠르게 확인할 수 있어요.
(학부모 인증 필요)

🎓 학원 탭
지역 학원 정보와 실제 학부모들의 후기를 확인해보세요.
별점과 후기로 학원을 쉽게 비교할 수 있어요.

💬 1:1 대화
다른 학부모님과 직접 메시지를 주고받을 수 있어요.

━━━━━━━━━━━━━━━━━━━━━
⚠️ 이용 주의사항
━━━━━━━━━━━━━━━━━━━━━

✅ MomsTalk는 익명 커뮤니티입니다.
개인 정보(이름, 연락처, 주소 등)는 공유하지 마세요.

✅ 학부모 인증이 필요한 서비스입니다.
알림장, 가정통신문 등 학교 발송 문서 캡처로 인증하실 수 있어요.

✅ 아래 행위는 제재 대상입니다.
• 타인 비방·욕설·혐오 발언
• 허위 정보 유포 및 명예훼손
• 상업적 광고·홍보 (협력 학원 제외)
• 개인정보 무단 공유
• 도배·스팸 게시글

신고 누적 5건 시 자동으로 게시글이 숨겨지며,
운영자 검토 후 경고·정지·영구 차단 조치가 이루어질 수 있습니다.

✅ 건강한 소통 문화를 함께 만들어요!
서로 존중하고 배려하는 학부모 커뮤니티가 되도록 노력 부탁드려요.

━━━━━━━━━━━━━━━━━━━━━
📞 문의 및 신고
━━━━━━━━━━━━━━━━━━━━━

불편한 게시물은 게시글 우측 상단 ··· 버튼으로 신고해 주세요.

감사합니다 🙏
MomsTalk 운영팀''';

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: _defaultTitle);
    _contentCtrl = TextEditingController(text: _defaultContent);
  }

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
      final token = await ref.read(tokenStorageProvider).read(AppConstants.tokenKey);
      await userDio.post('/posts', data: {
        'board_type': _boardType,
        'title': _titleCtrl.text.trim(),
        'content': _contentCtrl.text.trim(),
        'is_anonymous': false,
      }, options: Options(headers: {'Authorization': 'Bearer $token'}));
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
            DropdownMenuItem(value: 'notice', child: Text('📢 공지 (지역 게시판 상단 고정)')),
            DropdownMenuItem(value: 'free', child: Text('전체 게시판')),
            DropdownMenuItem(value: 'region', child: Text('지역 게시판')),
            DropdownMenuItem(value: 'school', child: Text('학교 게시판')),
            DropdownMenuItem(value: 'grade', child: Text('학년 게시판')),
          ],
          onChanged: (v) => setState(() => _boardType = v!),
        ),
        if (_boardType == 'notice')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: Colors.orange.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '공지글은 지역 게시판 최상단에 고정되며, 첫 로그인 시 팝업으로 표시됩니다.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                ),
              ),
            ]),
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

// ── 유저 상세 패널 (ExpansionTile 내부) ─────────────────────────────

class _UserDetailPanel extends ConsumerStatefulWidget {
  final int userId;
  final Map<String, dynamic> summary;
  final VoidCallback onApprove;
  final void Function(int days) onSuspend;
  final VoidCallback onBan;
  final VoidCallback onUnban;

  const _UserDetailPanel({
    required this.userId,
    required this.summary,
    required this.onApprove,
    required this.onSuspend,
    required this.onBan,
    required this.onUnban,
  });

  @override
  ConsumerState<_UserDetailPanel> createState() => _UserDetailPanelState();
}

class _UserDetailPanelState extends ConsumerState<_UserDetailPanel> {
  Map<String, dynamic>? _detail;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ref.read(adminDioProvider).get('/admin/users/${widget.userId}');
      if (mounted) setState(() => _detail = Map<String, dynamic>.from(resp.data as Map));
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBanned = widget.summary['is_banned'] == true;
    final isMember = widget.summary['member_grade'] == 'member';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('학교: ${widget.summary['school_name'] ?? '-'} ${widget.summary['grade'] ?? ''}학년',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text('가입: ${widget.summary['created_at'] ?? '-'}',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        if (widget.summary['suspended_until'] != null)
          Text('정지 해제: ${widget.summary['suspended_until']}',
              style: const TextStyle(fontSize: 12, color: Colors.deepOrange)),
        const SizedBox(height: 6),
        if (_detail != null)
          Text('게시글 ${_detail!['post_count'] ?? 0}개 · 경고 ${_detail!['warning_count'] ?? 0}회',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        if (_loading)
          const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else if (_detail != null && (_detail!['warnings'] as List? ?? []).isNotEmpty) ...[
          const Text('경고/제재 이력', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ...((_detail!['warnings'] as List).take(3).map((w) {
            final wm = Map<String, dynamic>.from(w as Map);
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, size: 13, color: Colors.orange.shade700),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('${wm['warning_type']} — ${wm['reason'] ?? ''}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            );
          })),
          const SizedBox(height: 6),
        ],
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (!isBanned) ...[
            if (!isMember)
              _ActionChip('정회원 승인', Colors.green, widget.onApprove),
            _ActionChip('7일 정지', Colors.orange, () => widget.onSuspend(7)),
            _ActionChip('30일 정지', Colors.deepOrange, () => widget.onSuspend(30)),
            _ActionChip('영구 차단', Colors.red, widget.onBan),
          ] else
            _ActionChip('차단 해제', Colors.green, widget.onUnban),
        ]),
      ]),
    );
  }
}
