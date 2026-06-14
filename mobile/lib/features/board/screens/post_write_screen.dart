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
      final resp = await dio.post('/posts', data: {
        'board_type': widget.boardType,
        'title': _titleCtrl.text.trim(),
        'content': _contentCtrl.text.trim(),
        'is_anonymous': _isAnonymous,
      });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('글쓰기'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('등록'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
