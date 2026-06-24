import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';

class PostWriteScreen extends ConsumerStatefulWidget {
  final String boardType;
  const PostWriteScreen({super.key, required this.boardType});

  @override
  ConsumerState<PostWriteScreen> createState() => _PostWriteScreenState();
}

class _PostWriteScreenState extends ConsumerState<PostWriteScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _tagSearchCtrl = TextEditingController();
  bool _isAnonymous = true;
  bool _submitting = false;

  // 선택된 태그 (DB canonical 값 — 학교명 or 지역명 or "N학년")
  final Set<String> _selectedTags = {};

  // 내 프로필 태그 (빠른 선택용)
  List<String> _myTags = [];

  // 검색 자동완성
  List<_TagSuggestion> _suggestions = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadMyTags();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _tagSearchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadMyTags() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/auth/me');
      final p = resp.data as Map<String, dynamic>;
      final tags = <String>[];
      final region = p['region'] as String?;
      final school = p['school_name'] as String?;
      final grade = p['grade'] as int?;
      if (region != null && region.isNotEmpty) tags.add(region);
      if (school != null && school.isNotEmpty) tags.add(school);
      if (grade != null) tags.add('$grade학년');
      if (mounted) setState(() => _myTags = tags);
    } catch (_) {}
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _fetchSuggestions(q));
  }

  Future<void> _fetchSuggestions(String q) async {
    if (!mounted) return;
    setState(() => _searching = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/schools/search', queryParameters: {'q': q});
      final results = (resp.data as List).cast<Map<String, dynamic>>();

      // 학교명 + 지역명(중복 제거) 추출
      final suggestions = <_TagSuggestion>[];
      final seenRegions = <String>{};
      for (final r in results.take(10)) {
        final name = r['school_name'] as String? ?? '';
        final region = r['region'] as String? ?? '';
        if (name.isNotEmpty) {
          suggestions.add(_TagSuggestion(label: name, subtitle: region, value: name, type: '학교'));
        }
        if (region.isNotEmpty && seenRegions.add(region)) {
          suggestions.add(_TagSuggestion(label: region, subtitle: '지역', value: region, type: '지역'));
        }
      }
      if (mounted) setState(() => _suggestions = suggestions);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _addTag(String value) {
    if (_selectedTags.length >= 5) return;
    if (value.isEmpty) return;
    setState(() {
      _selectedTags.add(value);
      _suggestions = [];
      _tagSearchCtrl.clear();
    });
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty || _contentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 입력해주세요.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final dio = ref.read(dioProvider);
      final body = {
        'board_type': widget.boardType,
        'title': _titleCtrl.text.trim(),
        'content': _contentCtrl.text.trim(),
        'is_anonymous': _isAnonymous,
        'mention_tags': _selectedTags.toList(),
      };
      final resp = await dio.post('/posts', data: body);
      final postId = resp.data['id'];
      if (mounted) context.go('/board/$postId');
    } on DioException catch (e) {
      if (mounted) {
        final data = e.response?.data;
        String msg = '';
        if (data is Map) {
          final raw = data['detail'];
          if (raw is String) {
            msg = raw;
          } else if (raw is List && raw.isNotEmpty) {
            msg = (raw as List).map((item) => (item as Map)['msg'] as String? ?? '').join('\n');
          }
        }
        if (msg.isEmpty) msg = '오류 ${e.response?.statusCode ?? ''}: ${e.message}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAddMore = _selectedTags.length < 5;
    final myUnselected = _myTags.where((t) => !_selectedTags.contains(t)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('글쓰기'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('등록'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(hintText: '제목', border: InputBorder.none),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _contentCtrl,
                  decoration: const InputDecoration(hintText: '내용을 입력해주세요.', border: InputBorder.none),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
            ),
            const Divider(height: 1),

            // ── @태그 섹션 ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(
                      '@태그',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '해당 지역·학교 게시판 상단에 노출됩니다 (최대 5개)',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
                    ),
                  ]),
                  const SizedBox(height: 8),

                  // 선택된 태그 칩
                  if (_selectedTags.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _selectedTags.map((tag) => Chip(
                        label: Text('@$tag', style: const TextStyle(fontSize: 13)),
                        onDeleted: () => setState(() => _selectedTags.remove(tag)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        visualDensity: VisualDensity.compact,
                      )).toList(),
                    ),

                  // 내 프로필 빠른 선택 (선택 안된 것만)
                  if (myUnselected.isNotEmpty && canAddMore) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: myUnselected.map((tag) => ActionChip(
                        avatar: const Icon(Icons.add, size: 14),
                        label: Text('@$tag', style: const TextStyle(fontSize: 12)),
                        onPressed: () => _addTag(tag),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.4)),
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                      )).toList(),
                    ),
                  ],

                  // 검색 필드
                  if (canAddMore) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: _tagSearchCtrl,
                      decoration: InputDecoration(
                        hintText: '다른 학교·지역 검색 (예: 강남구, 행복초)',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searching
                            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
                            : _tagSearchCtrl.text.isNotEmpty
                                ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _tagSearchCtrl.clear(); setState(() => _suggestions = []); })
                                : null,
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ],

                  // 자동완성 결과
                  if (_suggestions.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: Theme.of(context).colorScheme.surface,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final s = _suggestions[i];
                          return ListTile(
                            dense: true,
                            leading: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: s.type == '학교'
                                    ? Colors.blue.withOpacity(0.12)
                                    : Colors.green.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(s.type, style: TextStyle(fontSize: 11, color: s.type == '학교' ? Colors.blue : Colors.green, fontWeight: FontWeight.w600)),
                            ),
                            title: Text('@${s.label}', style: const TextStyle(fontSize: 14)),
                            subtitle: s.type == '학교' ? Text(s.subtitle, style: const TextStyle(fontSize: 12)) : null,
                            onTap: () => _addTag(s.value),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            const Divider(height: 1),
            SwitchListTile(
              value: _isAnonymous,
              onChanged: (v) => setState(() => _isAnonymous = v),
              title: const Text('익명으로 게시'),
              subtitle: const Text('작성자 닉네임이 표시되지 않습니다.'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagSuggestion {
  final String label;
  final String subtitle;
  final String value;
  final String type; // '학교' | '지역'
  const _TagSuggestion({required this.label, required this.subtitle, required this.value, required this.type});
}
