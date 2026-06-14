import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/constants.dart';

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
    const storage = FlutterSecureStorage();
    await storage.deleteAll();
    if (mounted) context.go('/auth/phone');
  }

  String _schoolTypeLabel(String? type) {
    switch (type) {
      case 'elementary': return '초등학교';
      case 'middle': return '중학교';
      case 'high': return '고등학교';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 정보'),
        actions: [
          TextButton(
            onPressed: _logout,
            child: const Text('로그아웃', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? const Center(child: Text('정보를 불러올 수 없습니다.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
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
                            _row(Icons.location_on_outlined, '지역', _profile!['region'] ?? '-'),
                            const SizedBox(height: 8),
                            _row(Icons.school_outlined, '학교',
                                '${_profile!['school_name'] ?? '-'} (${_schoolTypeLabel(_profile!['school_type'])})'),
                            const SizedBox(height: 8),
                            _row(Icons.grade_outlined, '학년', '${_profile!['grade'] ?? '-'}학년'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.edit_location_outlined),
                        title: const Text('지역·학교·학년 변경'),
                        subtitle: const Text('월 1회 변경 가능', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EditProfileScreen(profile: _profile!),
                            ),
                          );
                          _load();
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: const Text('닉네임 변경'),
                        subtitle: Text(_profile!['nickname'] ?? ''),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await showDialog(
                            context: context,
                            builder: (_) => _NicknameDialog(
                              nickname: _profile!['nickname'] ?? '',
                              ref: ref,
                            ),
                          );
                          _load();
                        },
                      ),
                    ),
                  ],
                ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('변경 실패: $e')));
      }
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
// 지역·학교·학년 편집 화면 (별도 페이지)
// ──────────────────────────────────────────────────────────────────

enum _EditStep { region, school }

class EditProfileScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> profile;
  const EditProfileScreen({super.key, required this.profile});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  _EditStep _step = _EditStep.region;

  String? _selectedProvince;
  String? _selectedRegion;

  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _schools = [];
  Map<String, dynamic>? _selectedSchool;
  int _grade = 1;
  bool _searching = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _grade = widget.profile['grade'] ?? 1;
    _selectedRegion = widget.profile['region'];
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _searchCtrl.text.trim();
    if (keyword.length < 2) return;
    setState(() { _searching = true; _schools = []; });
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/schools/search', queryParameters: {'keyword': keyword});
      setState(() => _schools = List<Map<String, dynamic>>.from(resp.data));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    final school = _selectedSchool;
    final region = _selectedRegion;
    if (school == null || region == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지역과 학교를 모두 선택해주세요.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/auth/me/profile', data: {
        'region': region,
        'school_code': school['school_code'],
        'school_name': school['school_name'],
        'grade': _grade,
        'school_type': school['school_type'],
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('정보가 변경되었습니다.')));
        Navigator.pop(context);
      }
    } catch (e) {
      final msg = e.toString().contains('월 1회') || e.toString().contains('429')
          ? '월 1회만 변경할 수 있습니다.'
          : '변경 실패: $e';
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == _EditStep.region ? '지역 선택' : '학교·학년 선택'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step == _EditStep.school) {
              setState(() { _step = _EditStep.region; _selectedSchool = null; });
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: _step == _EditStep.region ? _buildRegionStep() : _buildSchoolStep(),
    );
  }

  Widget _buildRegionStep() {
    final provinces = AppConstants.regions.keys.toList();
    final cities = _selectedProvince != null
        ? AppConstants.regions[_selectedProvince]!
        : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('지역을 선택해주세요.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700])),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: ListView.builder(
                  itemCount: provinces.length,
                  itemBuilder: (_, i) {
                    final p = provinces[i];
                    final selected = _selectedProvince == p;
                    return ListTile(
                      dense: true,
                      title: Text(p, style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      )),
                      selected: selected,
                      selectedTileColor:
                          Theme.of(context).colorScheme.primaryContainer.withAlpha(100),
                      onTap: () => setState(() {
                        _selectedProvince = p;
                        _selectedRegion = null;
                      }),
                    );
                  },
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: cities.length,
                  itemBuilder: (_, i) {
                    final c = cities[i];
                    final selected = _selectedRegion == c;
                    return ListTile(
                      dense: true,
                      title: Text(c,
                          style: TextStyle(
                            fontSize: 14,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          )),
                      trailing: selected
                          ? Icon(Icons.check,
                              color: Theme.of(context).colorScheme.primary,
                              size: 18)
                          : null,
                      onTap: () => setState(() => _selectedRegion = c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedRegion != null
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[300],
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _selectedRegion == null
                ? null
                : () => setState(() => _step = _EditStep.school),
            child: Text(_selectedRegion != null
                ? '$_selectedRegion 선택 완료 →'
                : '지역을 선택해주세요'),
          ),
        ),
      ],
    );
  }

  Widget _buildSchoolStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            const Icon(Icons.location_on, size: 16, color: Colors.grey),
            const SizedBox(width: 4),
            Text(_selectedRegion ?? '',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: '학교명 검색 (2자 이상)',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _search,
              child: const Text('검색'),
            ),
          ]),
        ),
        if (_searching) const LinearProgressIndicator(),
        Expanded(
          child: _schools.isEmpty && !_searching
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.search, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text(
                      '학교명을 입력하고 검색 버튼을 눌러주세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ]),
                )
              : ListView.builder(
                  itemCount: _schools.length,
                  itemBuilder: (_, i) {
                    final s = _schools[i];
                    final selected =
                        _selectedSchool?['school_code'] == s['school_code'];
                    return ListTile(
                      title: Text(s['school_name']),
                      subtitle: Text(s['address'] ?? '',
                          style: const TextStyle(fontSize: 12)),
                      trailing: selected
                          ? Icon(Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () => setState(() => _selectedSchool = s),
                    );
                  },
                ),
        ),
        if (_selectedSchool != null) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DropdownButtonFormField<int>(
              value: _grade,
              decoration: const InputDecoration(
                labelText: '학년',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: List.generate(6, (i) => i + 1)
                  .map((g) => DropdownMenuItem(value: g, child: Text('$g학년')))
                  .toList(),
              onChanged: (v) => setState(() => _grade = v!),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: (_selectedSchool != null && !_saving)
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[300],
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: (_selectedSchool == null || _saving) ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('변경 저장'),
          ),
        ),
      ],
    );
  }
}
