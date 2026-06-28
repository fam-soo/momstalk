import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../../../core/constants.dart';
import 'post_list_widget.dart';

class RegionBoardScreen extends ConsumerStatefulWidget {
  const RegionBoardScreen({super.key});

  @override
  ConsumerState<RegionBoardScreen> createState() => _RegionBoardScreenState();
}

class _RegionBoardScreenState extends ConsumerState<RegionBoardScreen> {
  bool _loading = true;
  bool _isMember = false;
  bool _isLurker = false;
  String _region = '';
  List<Map<String, dynamic>> _previewPosts = [];
  List<Map<String, dynamic>> _notices = [];
  int _previewTaps = 0;
  static const _tapLimit = 2;
  static const _prefKey = 'preview_taps_region';
  static const _seenNoticePref = 'seen_notice_id';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _loadNotices() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/posts/notices');
      _notices = (resp.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}
  }

  Future<void> _maybeShowNoticePopup() async {
    if (_notices.isEmpty || !mounted) return;
    final latest = _notices.first;
    final latestId = latest['id'] as int? ?? 0;
    final prefs = await SharedPreferences.getInstance();
    final seenId = prefs.getInt(_seenNoticePref) ?? 0;
    if (latestId <= seenId) return;
    await prefs.setInt(_seenNoticePref, latestId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.campaign_outlined, color: Color(0xFF4A90D9)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(latest['title'] as String? ?? '공지사항',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ]),
        content: SingleChildScrollView(
          child: Text(latest['content'] as String? ?? '',
              style: const TextStyle(height: 1.6, fontSize: 14)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _previewTaps = prefs.getInt(_prefKey) ?? 0;

    await _loadNotices();

    try {
      final storage = ref.read(tokenStorageProvider);
      final token = await storage.read(AppConstants.tokenKey);
      if (token == null) {
        await _loadPreview();
        return;
      }
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/auth/me');
      final profile = Map<String, dynamic>.from(resp.data as Map);
      final isMember = (profile['member_grade'] as String? ?? 'lurker') == 'member';
      final isAdmin = profile['is_admin'] as bool? ?? false;
      if (mounted) {
        setState(() {
          _isMember = isMember || isAdmin;
          _isLurker = !isMember && !isAdmin;
          _region = (profile['region'] as String?)?.isNotEmpty == true
              ? profile['region'] as String
              : '양천구';
          _loading = false;
        });
        if (_isMember) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowNoticePopup());
        }
      }
    } catch (_) {
      await _loadPreview();
    }
  }

  Future<void> _loadPreview() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/posts/preview', queryParameters: {'board_type': 'region'});
      final posts = (resp.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() { _previewPosts = posts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onPreviewTap(int postId) async {
    if (_isLurker) {
      if (!mounted) return;
      context.go('/auth/pending');
      return;
    }
    _previewTaps++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, _previewTaps);
    if (!mounted) return;
    if (_previewTaps >= _tapLimit) {
      context.go('/auth/login');
    } else {
      context.push('/board/$postId');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_isMember) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_region.isNotEmpty ? '$_region 게시판' : '지역 게시판',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(icon: const Icon(Icons.search), onPressed: () => context.push('/search')),
          ],
        ),
        body: Column(
          children: [
            if (_notices.isNotEmpty) _NoticeBar(notices: _notices),
            const Expanded(child: PostListWidget(boardType: 'region')),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/board/write?board_type=region'),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('글쓰기'),
        ),
      );
    }

    // lurker: 로그인은 됐으나 학부모 인증 미완료
    if (_isLurker) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('지역 게시판', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: _LurkerGate(onVerify: () => context.go('/auth/pending')),
      );
    }

    // 비회원 미리보기
    return Scaffold(
      appBar: AppBar(
        title: const Text('지역 게시판', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () => context.go('/auth/login'),
            child: const Text('로그인'),
          ),
        ],
      ),
      body: _PreviewBoard(
        posts: _previewPosts,
        boardLabel: '지역',
        onTap: _onPreviewTap,
        onJoin: () => context.go('/auth/login'),
      ),
    );
  }
}

class _PreviewBoard extends StatelessWidget {
  final List<Map<String, dynamic>> posts;
  final String boardLabel;
  final Future<void> Function(int postId) onTap;
  final VoidCallback onJoin;

  const _PreviewBoard({
    required this.posts,
    required this.boardLabel,
    required this.onTap,
    required this.onJoin,
  });

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // 미리보기 배너
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: theme.colorScheme.primaryContainer.withOpacity(0.4),
          child: Row(children: [
            Icon(Icons.visibility_outlined, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$boardLabel 게시판 인기글 미리보기 · 가입하면 모든 글을 볼 수 있어요',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
              ),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: posts.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.article_outlined, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('아직 게시글이 없어요', style: TextStyle(color: Colors.grey.shade500)),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onJoin,
                      icon: const Icon(Icons.person_add_outlined, size: 18),
                      label: const Text('가입하고 첫 글 쓰기'),
                    ),
                  ]),
                )
              : ListView.separated(
                  itemCount: posts.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    if (i == posts.length) {
                      return _JoinCta(onJoin: onJoin);
                    }
                    final post = posts[i];
                    return InkWell(
                      onTap: () => onTap(post['id'] as int),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(post['title'] as String? ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 8),
                            Row(children: [
                              Icon(Icons.favorite_outline, size: 13, color: Colors.grey[500]),
                              const SizedBox(width: 3),
                              Text('${post['like_count'] ?? 0}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                              const SizedBox(width: 12),
                              Icon(Icons.remove_red_eye_outlined, size: 13, color: Colors.grey[500]),
                              const SizedBox(width: 3),
                              Text('${post['view_count'] ?? 0}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                              const Spacer(),
                              Text(_relativeTime(post['created_at'] as String?),
                                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            ]),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── 공지 상단 고정 바 ─────────────────────────────────────────────

class _NoticeBar extends StatefulWidget {
  final List<Map<String, dynamic>> notices;
  const _NoticeBar({required this.notices});

  @override
  State<_NoticeBar> createState() => _NoticeBarState();
}

class _NoticeBarState extends State<_NoticeBar> {
  bool _expanded = false;

  void _showDetail(BuildContext ctx, Map<String, dynamic> notice) {
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.campaign_outlined, color: Color(0xFF4A90D9)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(notice['title'] as String? ?? '공지사항',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ]),
        content: SingleChildScrollView(
          child: Text(notice['content'] as String? ?? '',
              style: const TextStyle(height: 1.6, fontSize: 14)),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(_), child: const Text('닫기'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF4A90D9);
    return Material(
      color: primary.withOpacity(0.08),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                const Icon(Icons.campaign_outlined, size: 16, color: Color(0xFF4A90D9)),
                const SizedBox(width: 8),
                const Text('공지', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4A90D9))),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.notices.first['title'] as String? ?? '',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: Colors.grey),
              ]),
            ),
          ),
          if (_expanded)
            ...widget.notices.map((n) => InkWell(
              onTap: () => _showDetail(context, n),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: primary.withOpacity(0.15))),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  const SizedBox(width: 24),
                  const Icon(Icons.article_outlined, size: 14, color: Color(0xFF4A90D9)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(n['title'] as String? ?? '',
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ]),
              ),
            )),
          Divider(height: 1, color: primary.withOpacity(0.2)),
        ],
      ),
    );
  }
}

class _JoinCta extends StatelessWidget {
  final VoidCallback onJoin;
  const _JoinCta({required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_open_outlined, size: 36, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          const Text('더 많은 글을 보려면 가입하세요',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          Text('우리 지역 학부모들의 이야기를 확인해보세요',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onJoin,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('카카오로 시작하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 로그인은 됐으나 학부모 인증 미완료 ────────────────────────────────

class _LurkerGate extends StatelessWidget {
  final VoidCallback onVerify;
  const _LurkerGate({required this.onVerify});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_outlined, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            const Text(
              '학부모 인증이 필요해요',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              '지역 게시판은 학부모 인증 후 이용할 수 있어요.\n알림장·가정통신문 캡처로 간편하게 인증할 수 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, height: 1.6),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onVerify,
                icon: const Icon(Icons.upload_outlined),
                label: const Text('학부모 인증하기', style: TextStyle(fontSize: 15)),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
