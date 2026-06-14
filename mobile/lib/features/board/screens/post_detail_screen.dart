import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  final int postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  Map<String, dynamic>? _post;
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  final _commentCtrl = TextEditingController();
  bool _anonComment = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/posts/${widget.postId}'),
        dio.get('/posts/${widget.postId}/comments'),
      ]);
      setState(() {
        _post = Map<String, dynamic>.from(results[0].data);
        _comments = List<Map<String, dynamic>>.from(results[1].data);
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/posts/${widget.postId}/comments', data: {
        'content': text,
        'is_anonymous': _anonComment,
      });
      _commentCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  Future<void> _likePost() async {
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/posts/${widget.postId}/like');
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final post = _post!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('게시글'),
        actions: [
          PopupMenuButton(
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'report', child: Text('신고')),
            ],
            onSelected: (v) async {
              if (v == 'report') {
                final dio = ref.read(dioProvider);
                await dio.post('/posts/report', data: {
                  'target_type': 'post',
                  'target_id': widget.postId,
                  'reason': '부적절한 게시글',
                });
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다.')));
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(post['title'] ?? '', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(post['is_anonymous'] == true ? '익명' : (post['author']?['nickname'] ?? ''),
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const Divider(height: 24),
                Text(post['content'] ?? '', style: const TextStyle(fontSize: 15, height: 1.6)),
                const SizedBox(height: 16),
                Row(children: [
                  TextButton.icon(
                    onPressed: _likePost,
                    icon: const Icon(Icons.favorite_outline, size: 18),
                    label: Text('공감 ${post['like_count']}'),
                  ),
                ]),
                const Divider(height: 32),
                Text('댓글 ${_comments.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._comments.map((c) => _CommentTile(comment: c, postId: widget.postId, onDeleted: _load)),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                IconButton(
                  icon: Icon(_anonComment ? Icons.person_off_outlined : Icons.person_outlined),
                  tooltip: _anonComment ? '익명' : '닉네임',
                  onPressed: () => setState(() => _anonComment = !_anonComment),
                ),
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    decoration: const InputDecoration(hintText: '댓글을 입력하세요', isDense: true),
                    onSubmitted: (_) => _submitComment(),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: _submitComment),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends ConsumerWidget {
  final Map<String, dynamic> comment;
  final int postId;
  final VoidCallback onDeleted;

  const _CommentTile({required this.comment, required this.postId, required this.onDeleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                comment['is_anonymous'] == true ? '익명' : (comment['author_nickname'] ?? ''),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(comment['content'] ?? '', style: const TextStyle(fontSize: 14)),
            ]),
          ),
          TextButton(
            onPressed: () async {
              final dio = ref.read(dioProvider);
              await dio.post('/posts/$postId/comments/${comment['id']}/like');
              onDeleted();
            },
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 30)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.favorite_outline, size: 14),
              const SizedBox(width: 2),
              Text('${comment['like_count']}', style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ],
      ),
    );
  }
}
