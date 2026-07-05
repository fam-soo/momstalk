import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import 'post_detail_screen.dart' show showReportDialog;

class PostListWidget extends ConsumerStatefulWidget {
  final String boardType;
  final bool isAdmin;
  /// 다자녀 조회 시 특정 자녀 ID (null이면 active_child 사용)
  final int? childId;
  const PostListWidget({super.key, required this.boardType, this.isAdmin = false, this.childId});

  @override
  ConsumerState<PostListWidget> createState() => _PostListWidgetState();
}

class _PostListWidgetState extends ConsumerState<PostListWidget> {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int? _nextCursor;
  String _sort = 'recent';
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _nextCursor == null) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() { _loading = true; _error = null; _posts = []; _nextCursor = null; });
    } else {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }
    try {
      final dio = ref.read(dioProvider);
      final params = <String, dynamic>{
        'board_type': widget.boardType,
        'sort': _sort,
        'size': 20,
      };
      if (!reset && _nextCursor != null) params['cursor'] = _nextCursor;
      if (widget.childId != null) params['child_id'] = widget.childId;
      final resp = await dio.get('/posts', queryParameters: params);
      final data = Map<String, dynamic>.from(resp.data as Map);
      final items = (data['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final next = data['next_cursor'] as int?;
      if (mounted) {
        setState(() {
          _posts = reset ? items : [..._posts, ...items];
          _nextCursor = next;
        });
      }
    } catch (e) {
      if (reset && mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() { _loading = false; _loadingMore = false; });
    }
  }

  void _setSort(String sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          color: theme.colorScheme.surface,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(children: [
            _SortChip(label: '최신순', value: 'recent', current: _sort, onSelect: _setSort),
            const SizedBox(width: 8),
            _SortChip(label: '🔥 인기순', value: 'popular', current: _sort, onSelect: _setSort),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('오류: $_error', style: const TextStyle(color: Colors.red)))
                  : _posts.isEmpty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            const Text('아직 게시글이 없어요.\n첫 번째 글을 남겨보세요!',
                                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                          ]),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _load(reset: true),
                          child: ListView.separated(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _posts.length + (_nextCursor != null ? 1 : 0),
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              if (i == _posts.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                );
                              }
                              return PostCard(post: _posts[i], onRefresh: () => _load(reset: true), isAdmin: widget.isAdmin);
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final void Function(String) onSelect;
  const _SortChip({required this.label, required this.value, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
      selected: selected,
      onSelected: (_) => onSelect(value),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback onRefresh;
  final bool isAdmin;
  const PostCard({super.key, required this.post, required this.onRefresh, this.isAdmin = false});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late Map<String, dynamic> post = widget.post;
  bool _liking = false;

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post) post = widget.post;
  }

  Future<void> _toggleLike(WidgetRef ref) async {
    if (_liking) return;
    setState(() => _liking = true);
    final wasLiked = post['is_liked'] == true;
    final prevCount = post['like_count'] as int? ?? 0;
    setState(() {
      post = {
        ...post,
        'is_liked': !wasLiked,
        'like_count': wasLiked ? prevCount - 1 : prevCount + 1,
      };
    });
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/posts/${post['id']}/like');
      final data = Map<String, dynamic>.from(resp.data as Map);
      if (mounted) {
        setState(() {
          post = {...post, 'is_liked': data['is_liked'], 'like_count': data['like_count']};
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          post = {...post, 'is_liked': wasLiked, 'like_count': prevCount};
        });
      }
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  String _relativeTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분';
    if (diff.inHours < 24) return '${diff.inHours}시간';
    return DateFormat('MM.dd').format(dt);
  }

  Widget _adminLocationLabel(BuildContext ctx) {
    final boardType = post['board_type'] as String? ?? '';
    String? label;
    if (boardType == 'region') {
      label = post['author_region'] as String?;
    } else if (boardType == 'school') {
      label = post['author_school'] as String?;
    }
    if (label == null || label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(ctx).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('($label)', style: TextStyle(fontSize: 10, color: Theme.of(ctx).colorScheme.onSecondaryContainer)),
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _PostActionSheet(post: post, ref: ref, onRefresh: widget.onRefresh),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (ctx, ref, _) {
      final isPinned = post['is_pinned'] == true;
      final isHot = post['is_hot'] == true;
      final tags = (post['mention_tags'] as List<dynamic>? ?? []).cast<String>();
      final time = _relativeTime(post['created_at'] as String?);

      return InkWell(
        onTap: () => context.push('/board/${post['id']}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Theme.of(ctx).colorScheme.primaryContainer,
                  child: Icon(Icons.person, size: 14, color: Theme.of(ctx).colorScheme.primary),
                ),
                const SizedBox(width: 8),
                Text(
                  (post['author_display_name'] as String?)?.isNotEmpty == true
                      ? post['author_display_name'] as String
                      : (post['is_anonymous'] == true ? '익명' : '작성자'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (widget.isAdmin) ...[
                  const SizedBox(width: 4),
                  _adminLocationLabel(ctx),
                ],
                const Text(' · ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showOptions(ctx, ref),
                  child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.more_horiz, size: 18, color: Colors.grey)),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                if (isHot) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('🔥인기', style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w700)),
                ),
                if (isPinned && !isHot) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text('추천', style: TextStyle(fontSize: 10, color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.w700)),
                ),
                Expanded(child: Text(post['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 4, children: tags.map((t) => Text('@$t', style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.primary))).toList()),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _toggleLike(ref),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                      child: _Stat(
                        icon: post['is_liked'] == true ? Icons.favorite : Icons.favorite_outline,
                        value: post['like_count'] ?? 0,
                        color: post['is_liked'] == true ? Colors.red : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _Stat(icon: Icons.chat_bubble_outline, value: post['comment_count'] ?? 0),
                const SizedBox(width: 12),
                _Stat(icon: Icons.remove_red_eye_outlined, value: post['view_count'] ?? 0),
              ]),
            ],
          ),
        ),
      );
    });
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color? color;
  const _Stat({required this.icon, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color ?? Colors.grey[500]),
      const SizedBox(width: 3),
      Text('$value', style: TextStyle(fontSize: 12, color: color ?? Colors.grey[500])),
    ]);
  }
}

class _PostActionSheet extends StatelessWidget {
  final Map<String, dynamic> post;
  final WidgetRef ref;
  final VoidCallback onRefresh;
  const _PostActionSheet({required this.post, required this.ref, required this.onRefresh});

  Future<void> _block(BuildContext ctx) async {
    Navigator.pop(ctx);
    final authorId = post['author_id'] as int?;
    if (authorId == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('익명 게시글은 차단할 수 없습니다.')));
      return;
    }
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/users/$authorId/block');
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('이 회원의 글을 숨겼습니다.')));
      onRefresh();
    } catch (e) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('차단 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.flag_outlined, color: Colors.orange),
          title: const Text('게시물/회원 신고하기', style: TextStyle(color: Colors.orange)),
          onTap: () {
            Navigator.pop(ctx);
            showReportDialog(ctx, ref, targetType: 'post', targetId: post['id'] as int);
          },
        ),
        ListTile(
          leading: const Icon(Icons.hide_source_outlined, color: Colors.red),
          title: const Text('이 회원의 글 모두 숨기기', style: TextStyle(color: Colors.red)),
          onTap: () => _block(ctx),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
