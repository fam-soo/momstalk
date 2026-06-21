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
  bool _isAnonymous = true;
  bool _submitting = false;

  // free 게시판 전용: 선택된 @태그
  final Set<String> _selectedTags = {};
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    if (widget.boardType == 'free') {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/auth/me');
      if (mounted) setState(() => _profile = Map<String, dynamic>.from(resp.data));
    } catch (_) {}
  }

  List<({String label, String tag})> _availableTags() {
    if (_profile == null) return [];
    final tags = <({String label, String tag})>[];
    final region = _profile!['region'] as String?;
    final school = _profile!['school_name'] as String?;
    final schoolCode = _profile!['school_code'] as String?;
    final grade = _profile!['grade'] as int?;
    if (region != null) tags.add((label: '@$region', tag: 'region:$region'));
    if (school != null && schoolCode != null) tags.add((label: '@$school', tag: 'school:$schoolCode'));
    if (grade != null) tags.add((label: '@$grade학년', tag: 'grade:$grade'));
    return tags;
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
        if (widget.boardType == 'free') 'mention_tags': _selectedTags.toList(),
      };
      final resp = await dio.post('/posts', data: body);
      if (mounted) {
        context.pop();
        context.push('/board/${resp.data['id']}');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFree = widget.boardType == 'free';
    final availTags = _availableTags();

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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(hintText: '제목', border: InputBorder.none),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            Expanded(
              child: TextField(
                controller: _contentCtrl,
                decoration: const InputDecoration(hintText: '내용을 입력해주세요.', border: InputBorder.none),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
              ),
            ),
            const Divider(),
            // 전체 게시판: @태그 선택
            if (isFree && availTags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '@태그로 대상 지정 (선택한 그룹 유저에게 상단 노출)',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: availTags.map((t) {
                  final selected = _selectedTags.contains(t.tag);
                  return FilterChip(
                    label: Text(t.label),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selectedTags.add(t.tag);
                      } else {
                        _selectedTags.remove(t.tag);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              const Divider(),
            ],
            SwitchListTile(
              value: _isAnonymous,
              onChanged: (v) => setState(() => _isAnonymous = v),
              title: const Text('익명으로 게시'),
              subtitle: const Text('작성자 닉네임이 표시되지 않습니다.'),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}
