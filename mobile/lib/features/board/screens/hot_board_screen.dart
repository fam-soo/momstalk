import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/refresh_bus.dart';
import 'post_list_widget.dart' show PostCard;

/// 지역·학교·학원 게시판을 가로질러 인기글만 모아 보여주는 탭.
///
/// 초기 활성화 단계에서 학교 게시판은 잠겨 있고 개별 게시판 콘텐츠도 적어
/// 신규 유저가 "볼 게 없어서" 이탈하는 문제를 완화하기 위해, 원래 하단
/// 네비게이션의 '대화' 탭 자리를 대체해 넣었다 (대화 기능은 당분간 미사용).
class HotBoardScreen extends ConsumerStatefulWidget {
  const HotBoardScreen({super.key});

  @override
  ConsumerState<HotBoardScreen> createState() => _HotBoardScreenState();
}

class _HotBoardScreenState extends ConsumerState<HotBoardScreen> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/posts/hot');
      final data = Map<String, dynamic>.from(resp.data as Map);
      final items = (data['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() => _posts = items);
    } catch (_) {
      if (mounted) setState(() => _error = '인기글을 불러오지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _boardTypeLabel(String type) {
    switch (type) {
      case 'region': return '지역';
      case 'school': return '학교';
      case 'grade': return '학년';
      case 'free': return '전체';
      default: return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen<int>(boardRefreshSignal, (prev, next) {
      if (prev != null && prev != next) _load();
    });
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('🔥 인기'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.error_outline, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
                    ]),
                  ),
                )
              : _posts.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.local_fire_department_outlined, size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text('아직 인기글이 없어요.\n지역·학교·학원 게시판에 글을 남겨보세요!',
                            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _posts.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final post = _posts[i];
                          // 게시판 라벨을 별도 줄로 얹으면 항목당 3줄이 되어버려서,
                          // PostCard의 1번째 줄(작성자·시간) 앞에 함께 표시되도록 넘긴다.
                          return PostCard(
                            post: post,
                            onRefresh: _load,
                            boardTypeLabel: _boardTypeLabel(post['board_type'] as String? ?? ''),
                          );
                        },
                      ),
                    ),
    );
  }
}
