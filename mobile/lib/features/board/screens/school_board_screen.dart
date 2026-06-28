import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../../../core/constants.dart';
import 'post_list_widget.dart';

class SchoolBoardScreen extends ConsumerStatefulWidget {
  const SchoolBoardScreen({super.key});

  @override
  ConsumerState<SchoolBoardScreen> createState() => _SchoolBoardScreenState();
}

class _SchoolBoardScreenState extends ConsumerState<SchoolBoardScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _isMember = false;
  String _schoolName = '';
  int _grade = 1;
  List<Map<String, dynamic>> _previewPosts = [];
  int _previewTaps = 0;
  TabController? _tabController;
  static const _tapLimit = 2;
  static const _prefKey = 'preview_taps_school';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
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
        final tabs = TabController(length: 2, vsync: this);
        setState(() {
          _isMember = isMember || isAdmin;
          _schoolName = profile['school_name'] as String? ?? '';
          _grade = profile['grade'] as int? ?? 1;
          _tabController = tabs;
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
      final resp = await dio.get('/posts/preview', queryParameters: {'board_type': 'school'});
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
      context.go('/auth/school-select');
    } else {
      context.push('/board/$postId');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_isMember) {
      final tc = _tabController!;
      return Scaffold(
        appBar: AppBar(
          title: Text(_schoolName.isNotEmpty ? _schoolName : '학교 게시판',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(icon: const Icon(Icons.search), onPressed: () => context.push('/search')),
          ],
          bottom: TabBar(
            controller: tc,
            tabs: [
              const Tab(text: '학교'),
              Tab(text: '$_grade학년'),
            ],
          ),
        ),
        body: TabBarView(
          controller: tc,
          children: const [
            PostListWidget(boardType: 'school'),
            PostListWidget(boardType: 'grade'),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            final boardType = tc.index == 0 ? 'school' : 'grade';
            context.push('/board/write?board_type=$boardType');
          },
          icon: const Icon(Icons.edit_outlined),
          label: const Text('글쓰기'),
        ),
      );
    }

    // 비회원/lurker 미리보기
    return Scaffold(
      appBar: AppBar(
        title: const Text('학교 게시판', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: () => context.go('/auth/school-select'),
            child: const Text('학교 인증'),
          ),
        ],
      ),
      body: _SchoolPreviewBoard(
        posts: _previewPosts,
        onTap: _onPreviewTap,
        onCertify: () => context.go('/auth/school-select'),
      ),
    );
  }
}

class _SchoolPreviewBoard extends StatelessWidget {
  final List<Map<String, dynamic>> posts;
  final Future<void> Function(int postId) onTap;
  final VoidCallback onCertify;

  const _SchoolPreviewBoard({
    required this.posts,
    required this.onTap,
    required this.onCertify,
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: theme.colorScheme.primaryContainer.withOpacity(0.4),
          child: Row(children: [
            Icon(Icons.school_outlined, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '학교 게시판 인기글 미리보기 · 학부모 인증 후 모든 글을 볼 수 있어요',
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
                    Icon(Icons.school_outlined, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('아직 게시글이 없어요', style: TextStyle(color: Colors.grey.shade500)),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onCertify,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('학교 인증하기'),
                    ),
                  ]),
                )
              : ListView.separated(
                  itemCount: posts.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    if (i == posts.length) {
                      return _CertifyCta(onCertify: onCertify);
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

class _CertifyCta extends StatelessWidget {
  final VoidCallback onCertify;
  const _CertifyCta({required this.onCertify});

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
      child: Column(children: [
        Icon(Icons.school_outlined, size: 36, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        const Text('우리 학교 게시판 이용하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 6),
        Text('학부모 인증 후 우리 학교 · 학년 게시판을\n이용할 수 있어요',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onCertify,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('학교 검색으로 인증하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
      ]),
    );
  }
}
