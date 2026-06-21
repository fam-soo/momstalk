import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String _lastQ = '';

  Future<void> _search(String q) async {
    q = q.trim();
    if (q.isEmpty || q == _lastQ) return;
    _lastQ = q;
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/posts', queryParameters: {'board_type': 'free', 'q': q, 'size': 50});
      setState(() => _results = List<Map<String, dynamic>>.from(resp.data));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '게시글 검색',
            border: InputBorder.none,
            suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _ctrl.clear(); setState(() { _results = []; _lastQ = ''; }); })
                : null,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          onChanged: (v) => setState(() {}),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? Center(
                  child: Text(
                    _lastQ.isEmpty ? '검색어를 입력하세요' : '검색 결과가 없어요',
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final p = _results[i];
                    return ListTile(
                      title: Text(p['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      subtitle: Text('좋아요 ${p['like_count'] ?? 0}  댓글 ${p['comment_count'] ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      onTap: () => context.push('/board/${p['id']}'),
                    );
                  },
                ),
    );
  }
}
