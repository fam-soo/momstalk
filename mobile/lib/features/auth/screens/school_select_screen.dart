import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import 'capture_upload_screen.dart';

class SchoolSelectScreen extends ConsumerStatefulWidget {
  const SchoolSelectScreen({super.key});

  @override
  ConsumerState<SchoolSelectScreen> createState() => _SchoolSelectScreenState();
}

class _SchoolSelectScreenState extends ConsumerState<SchoolSelectScreen> {
  final _searchCtrl = TextEditingController();
  String? _selectedType; // null = 전체
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selected;
  int _grade = 1;
  int? _classNum;
  bool _loading = false;
  bool _searched = false;

  static const _typeOptions = [
    (null, '전체'),
    ('elementary', '초'),
    ('middle', '중'),
    ('high', '고'),
  ];

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('검색 오류: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // NEIS ORG_RDNMA에서 지역 단위 추출 (프론트 보조, 백엔드 region 필드 우선)
  String _extractRegion(String address) {
    final parts = address.split(' ');
    if (parts.isEmpty) return address;
    final province = parts[0];
    if (parts.length < 2) return province;
    final second = parts[1];
    // 특별시/광역시/특별자치시 → 구 단위
    if (province.endsWith('특별시') || province.endsWith('광역시') || province.endsWith('특별자치시')) {
      return second;
    }
    // 도/특별자치도 → 시/군 단위
    if (province.endsWith('도') || province.endsWith('특별자치도')) {
      if (second.endsWith('시') || second.endsWith('군')) return second;
    }
    return province;
  }

  void _proceed() {
    if (_selected == null) return;
    final address = _selected!['address'] as String? ?? '';
    // region: 백엔드가 SchoolSearchResult.region에 이미 담아서 내려줌
    final region = (_selected!['region'] as String? ?? '').isNotEmpty
        ? _selected!['region'] as String
        : _extractRegion(address);

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: CaptureUploadScreen(schoolInfo: {
          'school_code': _selected!['school_code'],
          'school_name': _selected!['school_name'],
          'school_type': _selected!['school_type'],
          'address': address,
          'region': region,
          'grade': _grade,
          'class_num': _classNum,
        }),
      ),
    ));
  }

  int get _maxGrade => _selected?['school_type'] == 'elementary' ? 6 : 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('학부모 인증 — 학교 검색')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 안내 헤더 ─────────────────────────────────
          Container(
            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: const Text(
              '지역·학교 게시판은 같은 동네·학교 학부모끼리만 모이는 공간이라, '
              '먼저 자녀가 다니는 학교를 등록해야 이용할 수 있어요.\n\n'
              '자녀가 다니는 학교를 검색하세요.\n학교명(예: 행복초) 또는 지역명(예: 강남구)으로 찾을 수 있어요.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),

          // ── 검색바 ────────────────────────────────────
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

          // ── 학교급 필터 칩 ─────────────────────────────
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
                    setState(() {
                      _selectedType = opt.$1;
                      _results = [];
                      _selected = null;
                    });
                    if (_searched) _search();
                  },
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ),

          if (_loading) const LinearProgressIndicator(),

          // ── 검색 결과 목록 ────────────────────────────
          Expanded(
            child: !_searched
                ? _SearchHint()
                : _results.isEmpty && !_loading
                    ? const Center(
                        child: Text('검색 결과가 없어요.\n다른 이름이나 지역으로 검색해보세요.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final s = _results[i];
                          final isSelected = _selected?['school_code'] == s['school_code'];
                          return ListTile(
                            leading: _SchoolTypeIcon(type: s['school_type'] as String? ?? ''),
                            title: Text(s['school_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(s['address'] ?? '', style: const TextStyle(fontSize: 12)),
                            trailing: isSelected
                                ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                                : null,
                            selected: isSelected,
                            selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35),
                            onTap: () => setState(() {
                              _selected = s;
                              _grade = 1;
                              _classNum = null;
                            }),
                          );
                        },
                      ),
          ),

          // ── 선택된 학교 정보 + 학년/반 선택 ─────────────
          if (_selected != null) ...[
            const Divider(height: 1),
            Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 선택된 학교 확인 배너
                  Row(children: [
                    Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: _selected!['school_name'],
                            style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                          ),
                          TextSpan(
                            text: ' (${_extractRegion(_selected!['address'] ?? '')}) 학부모님이시군요!',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // 학년 선택 — 버튼 행
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
                  // 반 선택 (드롭다운 유지)
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

          // ── 다음 버튼 ─────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: FilledButton(
              onPressed: _selected == null ? null : _proceed,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('다음 — 알림장 캡처 업로드', style: TextStyle(fontSize: 15)),
            ),
          ),
          ),
        ],
      ),
    );
  }
}

// ── 초기 검색 힌트 ─────────────────────────────────────

class _SearchHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '학교명 또는 지역명을 입력하세요',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            _HintChip(text: '행복초등학교'),
            const SizedBox(height: 8),
            _HintChip(text: '강남구'),
            const SizedBox(height: 8),
            _HintChip(text: '해운대구'),
          ],
        ),
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  final String text;
  const _HintChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
    );
  }
}

// ── 학교급 아이콘 ──────────────────────────────────────

class _SchoolTypeIcon extends StatelessWidget {
  final String type;
  const _SchoolTypeIcon({required this.type});

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
