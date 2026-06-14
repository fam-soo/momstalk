import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  Map<String, dynamic>? _me;
  bool _loading = true;
  final _commentCtrl = TextEditingController();
  bool _anonComment = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/posts/${widget.postId}'),
        dio.get('/posts/${widget.postId}/comments'),
        dio.get('/auth/me'),
      ]);
      setState(() {
        _post = Map<String, dynamic>.from(results[0].data);
        _comments = List<Map<String, dynamic>>.from(results[1].data);
        _me = Map<String, dynamic>.from(results[2].data);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
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

  Future<void> _scrapPost() async {
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/posts/${widget.postId}/scrap');
      await _load();
    } catch (_) {}
  }

  Future<void> _deletePost() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('게시글 삭제'),
        content: const Text('삭제한 게시글은 복구할 수 없습니다. 삭제하시겠어요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/posts/${widget.postId}');
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }

  Future<void> _editPost() async {
    final post = _post;
    if (post == null) return;

    final titleCtrl = TextEditingController(text: post['title']);
    final contentCtrl = TextEditingController(text: post['content']);

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('게시글 수정'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: '제목'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                decoration: const InputDecoration(labelText: '내용'),
                maxLines: 6,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (updated != true) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/posts/${widget.postId}', data: {
        'title': titleCtrl.text.trim(),
        'content': contentCtrl.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('수정 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final post = _post!;
    final myId = _me?['id'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('게시글'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  await _editPost();
                case 'delete':
                  await _deletePost();
                case 'scrap':
                  await _scrapPost();
                case 'report':
                  try {
                    final dio = ref.read(dioProvider);
                    await dio.post('/posts/report', data: {
                      'target_type': 'post',
                      'target_id': widget.postId,
                      'reason': '부적절한 게시글',
                    });
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다.')));
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('신고 실패: $e')));
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('수정')])),
              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('삭제', style: TextStyle(color: Colors.red))])),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'scrap',
                child: Row(children: [
                  Icon(post['is_scraped'] == true ? Icons.bookmark : Icons.bookmark_outline, size: 18),
                  const SizedBox(width: 8),
                  Text(post['is_scraped'] == true ? '스크랩 취소' : '스크랩'),
                ]),
              ),
              const PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_outlined, size: 18, color: Colors.orange), SizedBox(width: 8), Text('신고')])),
            ],
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
                Row(children: [
                  Text(
                    post['is_anonymous'] == true ? '익명' : (post['author']?['nickname'] ?? ''),
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const Spacer(),
                  Text('조회 ${post['view_count'] ?? 0}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
                const Divider(height: 24),
                Text(post['content'] ?? '', style: const TextStyle(fontSize: 15, height: 1.6)),
                const SizedBox(height: 16),
                Row(children: [
                  _ActionButton(
                    icon: post['is_liked'] == true ? Icons.favorite : Icons.favorite_outline,
                    label: '공감 ${post['like_count'] ?? 0}',
                    color: post['is_liked'] == true ? Colors.red : null,
                    onTap: _likePost,
                  ),
                  const SizedBox(width: 8),
                  _ActionButton(
                    icon: post['is_scraped'] == true ? Icons.bookmark : Icons.bookmark_outline,
                    label: '스크랩 ${post['scrap_count'] ?? 0}',
                    color: post['is_scraped'] == true ? Colors.amber[700] : null,
                    onTap: _scrapPost,
                  ),
                ]),
                const Divider(height: 32),
                Text('댓글 ${_comments.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._comments.map((c) => _CommentTile(comment: c, postId: widget.postId, myId: myId, onChanged: _load)),
              ],
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _anonComment = !_anonComment),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        _anonComment ? Icons.person_off_outlined : Icons.person_outlined,
                        color: _anonComment ? Colors.grey : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    decoration: const InputDecoration(hintText: '댓글을 입력하세요', isDense: true, border: OutlineInputBorder()),
                    onSubmitted: (_) => _submitComment(),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _submitComment,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.send, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: color ?? Colors.grey[600]),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 13, color: color ?? Colors.grey[600])),
          ]),
        ),
      ),
    );
  }
}

class _CommentTile extends ConsumerStatefulWidget {
  final Map<String, dynamic> comment;
  final int postId;
  final int? myId;
  final VoidCallback onChanged;

  const _CommentTile({required this.comment, required this.postId, required this.myId, required this.onChanged});

  @override
  ConsumerState<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends ConsumerState<_CommentTile> {
  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('댓글 삭제'),
        content: const Text('댓글을 삭제하시겠어요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/posts/${widget.postId}/comments/${widget.comment['id']}');
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final isAnon = c['is_anonymous'] == true;
    final authorName = isAnon ? '익명' : (c['author_nickname'] ?? '');
    final isPostAuthor = c['is_post_author'] == true;
    final isNested = c['parent_id'] != null;

    return Padding(
      padding: EdgeInsets.only(left: isNested ? 24.0 : 0, top: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isNested) const Icon(Icons.subdirectory_arrow_right, size: 16, color: Colors.grey),
          CircleAvatar(
            radius: 14,
            backgroundColor: isPostAuthor ? Theme.of(context).colorScheme.primaryContainer : Colors.grey[200],
            child: Icon(Icons.person, size: 14, color: isPostAuthor ? Theme.of(context).colorScheme.primary : Colors.grey),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(authorName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (isPostAuthor) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('작성자', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
              const SizedBox(height: 4),
              Text(c['content'] ?? '', style: const TextStyle(fontSize: 14)),
            ]),
          ),
          // 좋아요
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () async {
                final dio = ref.read(dioProvider);
                await dio.post('/posts/${widget.postId}/comments/${c['id']}/like');
                widget.onChanged();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(c['is_liked'] == true ? Icons.favorite : Icons.favorite_outline, size: 14,
                      color: c['is_liked'] == true ? Colors.red : Colors.grey),
                  const SizedBox(width: 2),
                  Text('${c['like_count'] ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ),
            ),
          ),
          // 삭제 (403이면 서버가 막음)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: _delete,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(Icons.delete_outline, size: 16, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
