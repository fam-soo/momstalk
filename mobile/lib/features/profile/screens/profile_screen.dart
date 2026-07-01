import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kakao_flutter_sdk_share/kakao_flutter_sdk_share.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api_client.dart';
import '../../../core/router.dart';
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
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/auth/invite/generate');
      final deeplink = resp.data['deeplink'] as String;
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => _InviteShareDialog(deeplink: deeplink),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('링크 생성 실패: $e')));
    }
  }

  String _schoolTypeLabel(String? type) {
    switch (type) {
      case 'elementary': return '초등학교';
      case 'middle': return '중학교';
      case 'high': return '고등학교';
      default: return '';
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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

        // ── 기본 프로필 카드 ──────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const CircleAvatar(radius: 28, child: Icon(Icons.person, size: 28)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(_profile!['nickname'] ?? '닉네임 없음',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        if (isAdmin) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFF4A90D9), borderRadius: BorderRadius.circular(4)),
                            child: const Text('관리자', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 4),
                      _TemperatureChip(
                        celsius: (_profile!['temperature'] as num?)?.toDouble() ?? 36.5,
                      ),
                    ],
                  )),
                ]),
                if (!isAdmin) ...[
                  const Divider(height: 24),
                  _row(Icons.location_on_outlined, '지역',
                      isMember ? (displayRegion ?? '-') : '미인증'),
                  const SizedBox(height: 8),
                  _row(Icons.school_outlined, '학교', () {
                      if (!isMember) return '미인증';
                      final name = displaySchool ?? '-';
                      return displayGrade != null ? '$name ($displayGrade학년)' : name;
                    }()),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── 지역·학교·학년 변경 + 심사 상태 통합 카드 (관리자 제외) ──────
        if (!isAdmin) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    isPending
                        ? Icons.hourglass_top_rounded
                        : isMember
                            ? Icons.edit_location_outlined
                            : Icons.verified_outlined,
                    color: isPending ? Colors.orange : null,
                  ),
                  title: Text(
                    isMember ? '지역·학교·학년 변경' : '학부모 인증 (학교 선택)',
                    style: isPending ? const TextStyle(color: Colors.orange) : null,
                  ),
                  subtitle: Text(
                    isPending
                        ? '심사 진행 중 — 탭하여 현황 확인'
                        : isMember
                            ? '월 1회 변경 가능'
                            : '학교를 검색하여 인증을 시작하세요',
                    style: TextStyle(
                      fontSize: 12,
                      color: isPending ? Colors.orange.shade700 : Colors.grey,
                    ),
                  ),
                  trailing: isPending
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: const Text('심사 중', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600)),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () => _onTapSchoolChange(isPending, isMember),
                ),
                if (isPending) ...[
                  const Divider(height: 1),
                  Container(
                    color: Colors.orange.shade50,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '알림장 캡처 검토 중입니다. 승인 시 푸시 알림으로 안내드립니다.',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                        ),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── 자녀 관리 (정회원) ────────────────────────────
          if (isMember) _ChildrenSection(profile: _profile!, onChanged: _load),
          if (isMember) const SizedBox(height: 8),
        ],

        // ── 빠른 실행 버튼 행 ──────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                _QuickAction(icon: Icons.bookmark_outline, label: '스크랩', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScrapListScreen()))),
                _QuickAction(icon: Icons.badge_outlined, label: '닉네임', onTap: () async {
                  await showDialog(context: context, builder: (_) => _NicknameDialog(nickname: _profile!['nickname'] ?? '', ref: ref));
                  _load();
                }),
                if (isMember && !isAdmin)
                  _QuickAction(icon: Icons.person_add_outlined, label: '친구초대', onTap: _generateInvite),
              ],
            ),
          ),
        ),
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

  Widget _row(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 18, color: Colors.grey),
      const SizedBox(width: 8),
      Text('$label  ', style: const TextStyle(color: Colors.grey, fontSize: 13)),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
    ]);
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
          padding: const EdgeInsets.symmetric(vertical: 12),
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
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }

  Future<void> _addChild() async {
    await showDialog(
      context: context,
      builder: (_) => _AddChildDialog(ref: ref),
    );
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.child_care, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('자녀 관리', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const Spacer(),
                if (_children.length < 5)
                  TextButton.icon(
                    onPressed: _loading ? null : _addChild,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('추가'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
              ],
            ),
            if (_children.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('등록된 자녀가 없습니다.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              )
            else
              Wrap(
                spacing: 8,
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
                      onSelected: (_) => _setActive(id),
                    ),
                  );
                }).toList(),
              ),
            if (_children.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('선택된 자녀의 학교 게시판이 활성화됩니다. 길게 눌러 삭제.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddChildDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _AddChildDialog({required this.ref});

  @override
  ConsumerState<_AddChildDialog> createState() => _AddChildDialogState();
}

class _AddChildDialogState extends ConsumerState<_AddChildDialog> {
  final _schoolCtrl = TextEditingController();
  String? _selectedSchoolCode;
  String? _selectedSchoolName;
  String? _selectedSchoolType;
  String? _selectedRegion;
  int _grade = 1;
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;
  bool _saving = false;

  @override
  void dispose() {
    _schoolCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchSchools(String q) async {
    if (q.length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/schools/search', queryParameters: {'q': q});
      if (mounted) {
        setState(() => _searchResults = List<Map<String, dynamic>>.from(resp.data));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    if (_selectedSchoolCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('학교를 선택해주세요.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/auth/me/children', data: {
        'school_code': _selectedSchoolCode,
        'school_name': _selectedSchoolName,
        'grade': _grade,
        'school_type': _selectedSchoolType,
        'region': _selectedRegion,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('추가 실패: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('자녀 추가'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _schoolCtrl,
              decoration: const InputDecoration(labelText: '학교 검색', prefixIcon: Icon(Icons.search)),
              onChanged: _searchSchools,
            ),
            if (_searching)
              const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)),
            if (_searchResults.isNotEmpty && _selectedSchoolCode == null)
              SizedBox(
                height: 160,
                child: ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (_, i) {
                    final s = _searchResults[i];
                    return ListTile(
                      dense: true,
                      title: Text(s['school_name'] as String? ?? '', style: const TextStyle(fontSize: 13)),
                      subtitle: Text(s['region'] as String? ?? '', style: const TextStyle(fontSize: 11)),
                      onTap: () {
                        setState(() {
                          _selectedSchoolCode = s['school_code'] as String?;
                          _selectedSchoolName = s['school_name'] as String?;
                          _selectedSchoolType = s['school_type'] as String?;
                          _selectedRegion = s['region'] as String?;
                          _schoolCtrl.text = _selectedSchoolName ?? '';
                          _searchResults = [];
                        });
                      },
                    );
                  },
                ),
              ),
            if (_selectedSchoolCode != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('학년: ', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _grade,
                    items: List.generate(6, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}학년'))),
                    onChanged: (v) => setState(() => _grade = v ?? 1),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('추가'),
        ),
      ],
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

      if (mounted) {
        ref.invalidate(userProfileProvider);
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
              child: Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _grade,
                    decoration: const InputDecoration(labelText: '학년', border: OutlineInputBorder(), isDense: true),
                    items: List.generate(_maxGrade, (i) => i + 1)
                        .map((g) => DropdownMenuItem(value: g, child: Text('$g학년')))
                        .toList(),
                    onChanged: (v) => setState(() => _grade = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    value: _classNum,
                    decoration: const InputDecoration(labelText: '반 (선택)', border: OutlineInputBorder(), isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('선택 안함')),
                      ...List.generate(15, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}반'))),
                    ],
                    onChanged: (v) => setState(() => _classNum = v),
                  ),
                ),
              ]),
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
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
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
  const _InviteShareDialog({required this.deeplink});

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
        description: '아래 버튼을 눌러 48시간 내 가입해주세요.',
        imageUrl: Uri.parse('https://momstalk.co.kr/icons/Icon-192.png'),
        link: link,
      ),
      buttons: [
        Button(title: '가입하기', link: link),
      ],
    );

    try {
      if (await ShareClient.instance.isKakaoTalkSharingAvailable()) {
        await ShareClient.instance.shareDefault(template: template);
      } else {
        // 웹 / KakaoTalk 미설치 → 카카오 공유 웹 페이지 열기
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
        const Text(
          '아래 링크를 공유해 주세요.\n48시간 내 1회만 사용 가능합니다.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
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
