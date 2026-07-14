import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../../../core/kst_time.dart';
import '../../../core/refresh_bus.dart';
import '../../../core/school_display.dart';
import 'post_detail_screen.dart' show showReportDialog;

class PostListWidget extends ConsumerStatefulWidget {
  final String boardType;
  final bool isAdmin;
  /// 다자녀 조회 시 특정 자녀 ID (null이면 active_child 사용)
  final int? childId;
  /// region 게시판 전용 그룹 필터: all | school_age | preschool
  final String childGroup;
  /// 정렬 칩 왼쪽에 같은 줄로 붙일 추가 필터(예: 지역 게시판의 초중고맘/미취학맘
  /// 그룹 필터). 정렬 칩과는 구분선으로 나눠 표시한다.
  final List<Widget>? extraFilterChips;
  /// 이 게시판 안에서의 검색어(별도 화면으로 이동하지 않는 인라인 검색용).
  final String? searchQuery;
  const PostListWidget({
    super.key,
    required this.boardType,
    this.isAdmin = false,
    this.childId,
    this.childGroup = 'all',
    this.extraFilterChips,
    this.searchQuery,
  });

  @override
  ConsumerState<PostListWidget> createState() => _PostListWidgetState();
}

class _PostListWidgetState extends ConsumerState<PostListWidget> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int? _nextCursor;
  String _sort = 'recent';
  final _scrollCtrl = ScrollController();

  // TabBarView 안에서 탭을 전환해도 상태(및 진행 중이던 로드)를 유지한다.
  // 이게 없으면 오프스크린으로 밀린 탭의 State가 임의로 폐기/재생성되면서
  // 첫 진입 시 이미 도착한 응답이 폐기된 위젯에 반영되어 "글이 있는데 안 보이다가
  // 필터를 누르면 보이는" 증상이 재현되었다.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant PostListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.childGroup != widget.childGroup || oldWidget.searchQuery != widget.searchQuery) {
      _load(reset: true);
    }
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
      if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) params['q'] = widget.searchQuery;
      if (widget.boardType == 'region' && widget.childGroup != 'all') {
        params['child_group'] = widget.childGroup;
      }
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
      if (reset && mounted) {
        // 403은 대개 "아직 잠긴 게시판"(예: 학교 게시판 언락 전) 같은 정상적인
        // 접근 제한 상태다. 서버 detail 메시지를 그대로 보여주고, 그 외
        // 예외는 원시 스택트레이스 대신 일반적인 안내 문구로 대체한다.
        final String friendlyError;
        if (e is DioException && e.response?.statusCode == 403) {
          final detail = e.response?.data is Map ? (e.response!.data['detail'] as String?) : null;
          friendlyError = detail ?? '이 게시판은 아직 이용할 수 없어요.';
        } else {
          friendlyError = '게시글을 불러오지 못했어요. 잠시 후 다시 시도해주세요.';
        }
        setState(() => _error = friendlyError);
      }
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
    super.build(context); // AutomaticKeepAliveClientMixin 필수 호출
    // 게시글 작성/자녀 추가/학교 변경 후 이 화면으로 돌아오거나, 이미 선택된
    // 탭을 다시 탭했을 때 목록을 새로 불러온다 (bumpBoardRefresh 참고).
    ref.listen<int>(boardRefreshSignal, (prev, next) {
      if (prev != null && prev != next) _load(reset: true);
    });
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          color: theme.colorScheme.surface,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              if (widget.extraFilterChips != null && widget.extraFilterChips!.isNotEmpty) ...[
                ...widget.extraFilterChips!,
                const SizedBox(height: 20, child: VerticalDivider(width: 17, thickness: 1)),
              ],
              _SortChip(label: '최신순', value: 'recent', current: _sort, onSelect: _setSort),
              const SizedBox(width: 8),
              _SortChip(label: '🔥 인기순', value: 'popular', current: _sort, onSelect: _setSort),
            ]),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.lock_outline, size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
                        ]),
                      ),
                    )
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
  /// 인기 탭처럼 여러 게시판 글이 한 목록에 섞일 때만 넘기는 게시판 종류
  /// 라벨(예: '지역'). null이면 표시하지 않는다.
  final String? boardTypeLabel;
  const PostCard({super.key, required this.post, required this.onRefresh, this.isAdmin = false, this.boardTypeLabel});

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
    final kst = parseServerTimeToKst(iso);
    if (kst == null) return '';
    final nowKst = DateTime.now().toUtc().add(kstOffset);
    final diff = nowKst.difference(kst);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분';
    if (diff.inHours < 24) return '${diff.inHours}시간';
    return DateFormat('MM.dd').format(kst);
  }

  Widget _adminLocationLabel(BuildContext ctx) {
    final boardType = post['board_type'] as String? ?? '';
    String? label;
    if (boardType == 'region') {
      label = post['author_region'] as String?;
    } else if (boardType == 'school') {
      label = shortSchoolName(post['author_school'] as String?);
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
      final isNotice = post['is_notice'] == true;
      final time = _relativeTime(post['created_at'] as String?);

      // 1줄: 작성자·시간(+게시판 라벨) — 2줄: 뱃지+제목. 예전엔 아바타 아이콘
      // (편집 기능 없음)·통계 줄·태그 줄까지 합쳐 4줄을 썼다. 통계(좋아요/
      // 댓글/조회)는 1번째 줄 우측으로 옮기고 태그 표시는 뺐다.
      return InkWell(
        onTap: () => context.push('/board/${post['id']}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                // 왼쪽: 작성자·시간 정보 — Expanded로 남는 공간을 모두 흡수시켜서
                // 오른쪽 통계 묶음이 글 길이와 무관하게 항상 우측 끝에 붙도록 한다
                // (Spacer만 쓰면 자식 위젯 조합에 따라 우측 정렬이 흔들리는 사례가 있었음).
                Expanded(
                  child: Row(children: [
                    if (widget.boardTypeLabel != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(widget.boardTypeLabel!,
                            style: TextStyle(fontSize: 10, color: Theme.of(ctx).colorScheme.onSecondaryContainer, fontWeight: FontWeight.w600)),
                      ),
                    ],
                    Flexible(
                      child: Text(
                        (post['author_display_name'] as String?)?.isNotEmpty == true
                            ? post['author_display_name'] as String
                            : (post['is_anonymous'] == true ? '익명' : '작성자'),
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if ((post['author_badge'] as String?)?.isNotEmpty == true) ...[
                      const SizedBox(width: 4),
                      _AuthorBadge(label: post['author_badge'] as String),
                    ],
                    if (widget.isAdmin) ...[
                      const SizedBox(width: 4),
                      _adminLocationLabel(ctx),
                    ],
                    const Text(' · ', style: TextStyle(color: Colors.grey, fontSize: 11.5)),
                    Text(time, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                  ]),
                ),
                // 오른쪽: 좋아요·댓글·조회수·더보기 — 항상 우측 끝 정렬 고정
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
                const SizedBox(width: 8),
                _Stat(icon: Icons.chat_bubble_outline, value: post['comment_count'] ?? 0),
                const SizedBox(width: 8),
                _Stat(icon: Icons.remove_red_eye_outlined, value: post['view_count'] ?? 0),
                GestureDetector(
                  onTap: () => _showOptions(ctx, ref),
                  child: const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.more_horiz, size: 16, color: Colors.grey)),
                ),
              ]),
              const SizedBox(height: 4),
              // 공지/인기/추천 배지를 2번째 줄 맨 왼쪽에, 그 다음 제목을 배치.
              Row(children: [
                if (isNotice) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('📌공지', style: TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.w700)),
                ),
                if (!isNotice && isHot) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('🔥인기', style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w700)),
                ),
                if (!isNotice && isPinned && !isHot) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text('추천', style: TextStyle(fontSize: 10, color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.w700)),
                ),
                Expanded(child: Text(post['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ],
          ),
        ),
      );
    });
  }
}

/// 작성자 자녀 상태 뱃지 — "미취학" / "2학년" 등. 닉네임 옆에 작게 표시.
class _AuthorBadge extends StatelessWidget {
  final String label;
  const _AuthorBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9.5, color: Theme.of(context).colorScheme.onTertiaryContainer, fontWeight: FontWeight.w600),
      ),
    );
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
