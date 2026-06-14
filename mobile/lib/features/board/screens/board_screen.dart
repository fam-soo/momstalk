import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';

/// 유저 프로필 정보를 캐싱하는 provider
final _userProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final resp = await dio.get('/auth/me');
  return Map<String, dynamic>.from(resp.data);
});

class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() => _currentTab = _tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<(String label, String boardType)> _buildTabs(Map<String, dynamic> profile) {
    final region = profile['region'] as String? ?? '지역';
    final school = profile['school_name'] as String? ?? '학교';
    final grade = profile['grade'] as int? ?? 1;

    // 학교 이름 축약 (OO초, OO중, OO고)
    String schoolShort = school;
    if (school.length > 6) {
      schoolShort = '${school.substring(0, 4)}…';
    }

    return [
      (region, 'region'),
      (schoolShort, 'school'),
      ('$grade학년', 'grade'),
      ('@학교질문', 'school_ask'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(_userProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const Scaffold(body: Center(child: Text('프로필을 불러올 수 없습니다.'))),
      data: (profile) {
        final tabs = _buildTabs(profile);
        return Scaffold(
          appBar: AppBar(
            title: const Text('MomsTalk'),
            bottom: TabBar(
              controller: _tabController,
              tabs: tabs.map((t) => Tab(text: t.$1)).toList(),
              isScrollable: false,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.account_circle_outlined),
                tooltip: '내 정보',
                onPressed: () => context.push('/profile'),
              ),
            ],
          ),
          body: TabBarView(
            controller: _tabController,
            children: tabs.map((t) => _PostList(boardType: t.$2)).toList(),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => context.push('/board/write', extra: tabs[_currentTab].$2),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('글쓰기'),
          ),
        );
      },
    );
  }
}

class _PostList extends ConsumerStatefulWidget {
  final String boardType;
  const _PostList({required this.boardType});

  @override
  ConsumerState<_PostList> createState() => _PostListState();
}

class _PostListState extends ConsumerState<_PostList> {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/posts', queryParameters: {'board_type': widget.boardType});
      setState(() => _posts = List<Map<String, dynamic>>.from(resp.data));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('오류: $_error', style: const TextStyle(color: Colors.red)));
    if (_posts.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('아직 게시글이 없어요.\n첫 번째 글을 남겨보세요!',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _posts.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final p = _posts[i];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.push('/board/${p['id']}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(p['is_anonymous'] == true ? '익명' : '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const Text('  •  ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('댓글 ${p['comment_count'] ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const Text('  •  ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const Icon(Icons.favorite_outline, size: 12, color: Colors.grey),
                      const SizedBox(width: 2),
                      Text('${p['like_count'] ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const Text('  •  ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('조회 ${p['view_count'] ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
