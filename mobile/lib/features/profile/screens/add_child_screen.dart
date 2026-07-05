import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../auth/screens/capture_upload_screen.dart';

// 자녀 추가 전용 화면 — go_router 라우트로 등록되어야 autofocus/텍스트 입력이 정상 동작
class AddChildScreen extends ConsumerStatefulWidget {
  const AddChildScreen({super.key});

  @override
  ConsumerState<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends ConsumerState<AddChildScreen> {
  final _searchCtrl = TextEditingController();
  String? _selectedType;
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selected;
  int _grade = 1;
  bool _loading = false;
  bool _searched = false;
  bool _saving = false;
  bool _isTrusted = false;

  static const _typeOptions = [
    (null, '전체'),
    ('elementary', '초'),
    ('middle', '중'),
    ('high', '고'),
  ];

  @override
  void initState() {
    super.initState();
    _loadTrustedStatus();
  }

  Future<void> _loadTrustedStatus() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/auth/me');
      final p = resp.data as Map<String, dynamic>;
      if (mounted) setState(() => _isTrusted = p['is_trusted'] as bool? ?? false);
    } catch (_) {}
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
    final address = _selected!['address'] as String? ?? '';
    final region = (_selected!['region'] as String? ?? '').isNotEmpty
        ? _selected!['region'] as String
        : _extractRegion(address);
    final schoolInfo = {
      'school_code': _selected!['school_code'],
      'school_name': _selected!['school_name'],
      'grade': _grade,
      'school_type': _selected!['school_type'] ?? 'elementary',
      'region': region,
    };

    // 관리자가 인증 면제(is_trusted)한 사용자는 사진 인증 없이 즉시 자녀 추가
    if (_isTrusted) {
      setState(() => _saving = true);
      try {
        final dio = ref.read(dioProvider);
        await dio.post('/auth/me/children', data: schoolInfo);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('자녀가 추가되었습니다.')),
          );
          context.pop(true);
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('추가 실패: $e')));
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    // 캡처(알림장 사진) 인증 화면으로 이동
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CaptureUploadScreen(
          schoolInfo: schoolInfo,
          captureType: 'child_add',
        ),
      ),
    );
    if (result == true && mounted) context.pop(true);
  }

  int get _maxGrade => _selected?['school_type'] == 'elementary' ? 6 : 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('자녀 추가 — 학교 검색')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: theme.colorScheme.primaryContainer.withOpacity(0.4),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: const Text(
              '자녀가 다니는 학교를 검색하세요.\n학교명(예: 행복초) 또는 지역명(예: 강남구)으로 찾을 수 있어요.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(children: [
              Expanded(
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
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _loading ? null : _search,
                style: FilledButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('검색'),
              ),
            ]),
          ),
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
          Expanded(
            child: !_searched
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.search, size: 56, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('학교명 또는 지역명 입력 후 검색 버튼을 누르세요',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                    ]),
                  )
                : _results.isEmpty && !_loading
                    ? const Center(child: Text('검색 결과가 없어요.\n다른 이름이나 지역으로 검색해보세요.',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final s = _results[i];
                          final isSelected = _selected?['school_code'] == s['school_code'];
                          return ListTile(
                            leading: _SchoolTypeChip(type: s['school_type'] as String? ?? ''),
                            title: Text(s['school_name'] as String? ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(s['address'] as String? ?? '',
                                style: const TextStyle(fontSize: 12)),
                            trailing: isSelected
                                ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                                : null,
                            selected: isSelected,
                            selectedTileColor: theme.colorScheme.primaryContainer.withOpacity(0.35),
                            onTap: () => setState(() { _selected = s; _grade = 1; }),
                          );
                        },
                      ),
          ),
          if (_selected != null) ...[
            const Divider(height: 1),
            Container(
              color: theme.colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selected!['school_name'] as String? ?? '',
                        style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  const Text('자녀 학년', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                                color: selected ? theme.colorScheme.primary : Colors.transparent,
                                border: Border.all(
                                  color: selected ? theme.colorScheme.primary : Colors.grey.shade300,
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
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isTrusted ? '자녀 추가' : '다음 — 인증 사진 업로드', style: const TextStyle(fontSize: 15)),
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
