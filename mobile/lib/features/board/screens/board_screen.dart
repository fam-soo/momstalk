import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';

const _tabs = [
  ('우리 반', 'class'),
  ('학년 전체', 'grade'),
  ('학교 전체', 'school'),
  ('지역 라운지', 'region'),
];

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
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() => _currentTab = _tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MomsTalk'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs.map((t) => Tab(text: t.$1)).toList(),
          isScrollable: false,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {}, // 프로필 화면 (추후 구현)
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((t) => _PostList(boardType: t.$2)).toList(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/board/write', extra: _tabs[_currentTab].$2),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('글쓰기'),
      ),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/posts', queryParameters: {'board_type': widget.boardType});
      setState(() => _posts = List<Map<String, dynamic>>.from(resp.data));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
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
          return ListTile(
            title: Text(p['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${p['is_anonymous'] == true ? '익명' : ''}  •  조회 ${p['view_count']}  •  댓글 ${p['comment_count']}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.favorite_outline, size: 14, color: Colors.grey),
              const SizedBox(width: 2),
              Text('${p['like_count']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
            onTap: () => context.push('/board/${p['id']}'),
          );
        },
      ),
    );
  }
}
