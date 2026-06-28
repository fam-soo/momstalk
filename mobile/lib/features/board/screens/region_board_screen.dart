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
  String _region = '';
  List<Map<String, dynamic>> _previewPosts = [];
  int _previewTaps = 0;
  static const _tapLimit = 2;
  static const _prefKey = 'preview_taps_region';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _previewTaps = prefs.getInt(_prefKey) ?? 0;

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
          _region = profile['region'] as String? ?? '';
          _loading = false;
        });
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
        body: const PostListWidget(boardType: 'region'),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/board/write?board_type=region'),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('글쓰기'),
        ),
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
