import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';

// ── 신고 카테고리 ─────────────────────────────────────

const _reportCategories = [
  ('SPAM',           '스팸/홍보'),
  ('OBSCENE',        '음란/선정적 내용'),
  ('ABUSE',          '욕설/비방/혐오'),
  ('PERSONAL_INFO',  '개인정보 노출'),
  ('MISINFORMATION', '허위 사실/명예훼손'),
  ('ILLEGAL',        '불법 정보 (마약/도박 등)'),
  ('OFF_TOPIC',      '주제와 무관한 게시물'),
  ('OTHER',          '기타'),
];

/// 공통 신고 다이얼로그.
/// [targetType]: "post" | "comment"
/// [targetId]: 대상 ID
Future<void> showReportDialog(
  BuildContext context,
  WidgetRef ref, {
  required String targetType,
  required int targetId,
}) async {
  String? selectedCategory;
  final otherCtrl = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('신고하기'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('신고 사유를 선택해주세요.', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 12),
              ..._reportCategories.map(
                (cat) => RadioListTile<String>(
                  title: Text(cat.$2, style: const TextStyle(fontSize: 14)),
                  value: cat.$1,
                  groupValue: selectedCategory,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => selectedCategory = v),
                ),
              ),
              if (selectedCategory == 'OTHER') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: otherCtrl,
                  decoration: const InputDecoration(
                    hintText: '기타 사유를 입력하세요',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: selectedCategory == null ? null : () => Navigator.pop(ctx, true),
            child: const Text('신고'),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true || selectedCategory == null) return;

  try {
    final dio = ref.read(dioProvider);
    await dio.post('/posts/report', data: {
      'target_type': targetType,
      'target_id': targetId,
      'category': selectedCategory,
      'reason': selectedCategory == 'OTHER' ? otherCtrl.text.trim() : '',
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다. 검토 후 조치됩니다.')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('신고 실패: $e')));
    }
  }
}

// ── 공용 액션 시트 ────────────────────────────────────

Future<void> showPostActions(
  BuildContext context,
  WidgetRef ref, {
  required int postId,
  required int? authorId,
  required String? authorNickname,
  required bool isMyPost,
  required VoidCallback onRefresh,
  VoidCallback? onDelete,
  VoidCallback? onEdit,
}) async {
  await showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        if (!isMyPost && authorId != null) ...[
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text('대화하기'),
            onTap: () async {
              Navigator.pop(context);
              try {
                final dio = ref.read(dioProvider);
                final resp = await dio.post('/conversations/$authorId');
                final convId = resp.data['id'] as int;
                final nick = resp.data['other_nickname'] as String? ?? authorNickname ?? '상대방';
                if (context.mounted) context.push('/dm/$convId', extra: nick);
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
              }
            },
          ),
        ],
        if (isMyPost) ...[
          if (onEdit != null) ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('수정'), onTap: () { Navigator.pop(context); onEdit(); }),
          if (onDelete != null) ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('삭제', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(context); onDelete(); }),
        ],
        if (!isMyPost) ...[
          ListTile(
            leading: const Icon(Icons.flag_outlined, color: Colors.orange),
            title: const Text('게시물/회원 신고하기', style: TextStyle(color: Colors.orange)),
            onTap: () {
              Navigator.pop(context);
              showReportDialog(context, ref, targetType: 'post', targetId: postId);
            },
          ),
          if (authorId != null) ListTile(
            leading: const Icon(Icons.hide_source_outlined, color: Colors.red),
            title: const Text('이 회원의 글 모두 숨기기', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(context);
              try {
                final dio = ref.read(dioProvider);
                await dio.post('/users/$authorId/block');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이 회원의 글을 숨겼습니다.')));
                  context.pop();
                }
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('차단 실패: $e')));
              }
            },
          ),
        ],
        const SizedBox(height: 8),
      ]),
    ),
  );
}

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
  static const _anonAllowedBoards = {'school', 'free', 'region'};
  bool _anonComment = false;

  bool get _anonCommentAllowed => _anonAllowedBoards.contains(_post?['board_type']);

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
    } on DioException catch (e) {
      if (mounted) {
        final data = e.response?.data;
        String msg = '';
        if (data is Map) {
          final raw = data['detail'];
          if (raw is String) {
            msg = raw;
          } else if (raw is List && raw.isNotEmpty) {
            msg = (raw as List).map((item) => (item as Map<dynamic, dynamic>)['msg'] as String? ?? '').join(', ');
          }
        }
        if (msg.isEmpty) msg = '오류 ${e.response?.statusCode ?? ''}: ${e.message}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
        );
      }
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/board'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => showPostActions(
              context, ref,
              postId: widget.postId,
              authorId: post['author_id'] as int?,
              authorNickname: post['author']?['nickname'] as String?,
              isMyPost: post['is_mine'] == true,
              onRefresh: _load,
              onEdit: _editPost,
              onDelete: _deletePost,
            ),
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
                    (post['author_display_name'] as String?)?.isNotEmpty == true
                        ? post['author_display_name'] as String
                        : (post['is_anonymous'] == true ? '익명' : (post['author']?['nickname'] ?? '')),
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
                if (_anonCommentAllowed)
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

class _CommentBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _CommentBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
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
  void _showCommentActions() {
    final c = widget.comment;
    final isMyComment = c['author_id'] == widget.myId;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          if (!isMyComment && c['author_id'] != null) ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text('대화하기'),
            onTap: () async {
              Navigator.pop(context);
              try {
                final dio = ref.read(dioProvider);
                final resp = await dio.post('/conversations/${c['author_id']}');
                final convId = resp.data['id'] as int;
                final nick = resp.data['other_nickname'] as String? ?? '상대방';
                if (context.mounted) context.push('/dm/$convId', extra: nick);
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
              }
            },
          ),
          if (isMyComment) ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('삭제', style: TextStyle(color: Colors.red)),
            onTap: () { Navigator.pop(context); _delete(); },
          ),
          if (!isMyComment) ...[
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orange),
              title: const Text('댓글/회원 신고하기', style: TextStyle(color: Colors.orange)),
              onTap: () {
                Navigator.pop(context);
                showReportDialog(context, ref, targetType: 'comment', targetId: c['id'] as int);
              },
            ),
            if (c['author_id'] != null) ListTile(
              leading: const Icon(Icons.hide_source_outlined, color: Colors.red),
              title: const Text('이 회원의 글 모두 숨기기', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                try {
                  final dio = ref.read(dioProvider);
                  await dio.post('/users/${c['author_id']}/block');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이 회원의 글을 숨겼습니다.')));
                    widget.onChanged();
                  }
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('차단 실패: $e')));
                }
              },
            ),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

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
    // 서버가 내려준 anon_label 사용 (글쓴이 / 익명1 / 익명2 ...)
    final authorName = isAnon
        ? (c['anon_label'] as String? ?? '익명')
        : (c['author_nickname'] as String? ?? '');
    final isPostAuthor = c['is_post_author'] == true;
    final isMine = c['is_mine'] == true;
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
                  _CommentBadge(label: '작성자', color: Theme.of(context).colorScheme.primary),
                ],
                if (isMine && !isPostAuthor) ...[
                  const SizedBox(width: 6),
                  _CommentBadge(label: '나', color: Colors.grey),
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
          // 더보기 (대화/신고/삭제)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => _showCommentActions(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(Icons.more_horiz, size: 16, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
