import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api_client.dart';
import '../../../core/constants.dart';
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(tokenStorageProvider).deleteAll();
    if (mounted) context.go('/auth/login');
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text(
          '탈퇴하면 모든 개인정보가 즉시 삭제됩니다.\n'
          '작성한 게시글·댓글은 익명 상태로 유지됩니다.\n\n'
          '정말 탈퇴하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('탈퇴'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/auth/me');
      await ref.read(tokenStorageProvider).deleteAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('탈퇴가 완료되었습니다.')),
        );
        context.go('/auth/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('탈퇴 처리 중 오류가 발생했습니다: $e')),
        );
      }
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
        builder: (_) => AlertDialog(
          title: const Text('초대 링크 생성 완료'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('아래 링크를 공유해 주세요.\n48시간 내 1회만 사용 가능합니다.', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            SelectableText(deeplink, style: const TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
          ],
        ),
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
    final isMember = (_profile!['member_grade'] as String? ?? 'lurker') == 'member';
    final isPending = _profile!['auth_pending'] as bool? ?? false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                      Text(_profile!['nickname'] ?? '닉네임 없음',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('매너온도 ${_profile!['manner_score'] ?? 36}°',
                          style: TextStyle(color: Colors.orange[700], fontSize: 13)),
                    ],
                  )),
                ]),
                const Divider(height: 24),
                _row(Icons.location_on_outlined, '지역',
                    isMember ? (_profile!['region'] ?? '-') : '미인증'),
                const SizedBox(height: 8),
                _row(Icons.school_outlined, '학교',
                    isMember
                        ? '${_profile!['school_name'] ?? '-'} (${_schoolTypeLabel(_profile!['school_type'])})'
                        : '미인증'),
                const SizedBox(height: 8),
                _row(Icons.grade_outlined, '학년',
                    isMember ? '${_profile!['grade'] ?? '-'}학년' : '미인증'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── 지역·학교·학년 변경 + 심사 상태 통합 카드 ──────
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

        // ── 스크랩 ────────────────────────────────────────
        Card(
          child: ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('스크랩한 게시글'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScrapListScreen()),
            ),
          ),
        ),

        // ── 초대 링크 (정회원만) ──────────────────────────
        if (isMember) ...[
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.person_add_outlined, color: Theme.of(context).colorScheme.primary),
              title: const Text('친구 초대 링크 발급'),
              subtitle: const Text('같은 학교 학부모를 초대하세요 (48시간 유효)', style: TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _generateInvite,
            ),
          ),
        ],
        const SizedBox(height: 8),

        // ── 닉네임 변경 ───────────────────────────────────
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('닉네임 변경'),
            subtitle: Text(_profile!['nickname'] ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await showDialog(
                context: context,
                builder: (_) => _NicknameDialog(nickname: _profile!['nickname'] ?? '', ref: ref),
              );
              _load();
            },
          ),
        ),
        const SizedBox(height: 8),

        // ── 서비스 정보 ───────────────────────────────────
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('이용약관'),
                trailing: const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
                onTap: () => launchUrl(
                  Uri.parse(AppConstants.termsOfServiceUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('개인정보처리방침'),
                trailing: const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
                onTap: () => launchUrl(
                  Uri.parse(AppConstants.privacyPolicyUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('앱 버전'),
                trailing: Text(
                  'v1.0.0',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── 로그아웃 / 탈퇴 ──────────────────────────────
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.orange),
                title: const Text('로그아웃', style: TextStyle(color: Colors.orange)),
                onTap: _logout,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.person_remove_outlined, color: Colors.red),
                title: const Text('회원 탈퇴', style: TextStyle(color: Colors.red)),
                subtitle: const Text('탈퇴 시 개인정보가 즉시 삭제됩니다',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                onTap: _deleteAccount,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
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
