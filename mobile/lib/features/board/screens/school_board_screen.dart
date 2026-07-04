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
    with TickerProviderStateMixin {
  bool _loading = true;
  bool _isMember = false;
  bool _isLurker = false; // 로그인 했지만 미인증
  String _schoolName = '';
  int _grade = 1;
  List<Map<String, dynamic>> _previewPosts = [];
  int _previewTaps = 0;
  int _lurkerReads = 0; // lurker 읽기 횟수 (계정당 1회, 초기화 없음)
  TabController? _tabController;
  // 다자녀 지원
  List<Map<String, dynamic>> _children = [];
  int _selectedChildIdx = 0; // 선택된 자녀 인덱스
  TabController? _childTabController;
  static const _tapLimit = 2;
  static const _prefKey = 'preview_taps_school';
  static const _lurkerReadKey = 'school_lurker_reads';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _childTabController?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _previewTaps = prefs.getInt(_prefKey) ?? 0;
    _lurkerReads = prefs.getInt(_lurkerReadKey) ?? 0;

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
        final children = (profile['children'] as List? ?? [])
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        // 자녀 수에 맞게 탭 컨트롤러 생성
        final subTabCount = 2; // 학교 전체 + N학년
        final tabs = (isMember || isAdmin) ? TabController(length: subTabCount, vsync: this) : null;
        final childTabs = (isMember || isAdmin) && children.length > 1
            ? TabController(length: children.length, vsync: this)
            : null;
        setState(() {
          _isMember = isMember || isAdmin;
          _isLurker = !isMember && !isAdmin;
          _schoolName = profile['school_name'] as String? ?? '';
          _grade = profile['grade'] as int? ?? 1;
          _children = children;
          _selectedChildIdx = 0;
          _tabController = tabs;
          _childTabController = childTabs;
          _loading = false;
        });
      }
    } catch (_) {
      await _loadPreview();
    }
  }

  Future<void> _onLurkerTap(int postId) async {
    final prefs = await SharedPreferences.getInstance();
    if (_lurkerReads >= 1) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('학부모 인증 후 이용 가능'),
          content: const Text('학교 게시판은 학부모 인증 정회원만 이용할 수 있어요.\n알림장 캡처로 간편하게 인증할 수 있습니다.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
            FilledButton(
              onPressed: () { Navigator.pop(ctx); context.go('/auth/school-select'); },
              child: const Text('인증하기'),
            ),
          ],
        ),
      );
      return;
    }
    _lurkerReads++;
    await prefs.setInt(_lurkerReadKey, _lurkerReads);
    if (!mounted) return;
    context.push('/board/$postId');
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
      final hasMultiChild = _children.length > 1;
      // 현재 선택된 자녀 정보
      final selChild = hasMultiChild && _selectedChildIdx < _children.length
          ? _children[_selectedChildIdx]
          : null;
      final displaySchool = selChild != null
          ? (selChild['school_name'] as String? ?? _schoolName)
          : _schoolName;
      final displayGrade = selChild != null
          ? (selChild['grade'] as int? ?? _grade)
          : _grade;
      final selectedChildId = selChild?['id'] as int?;

      return Scaffold(
        appBar: AppBar(
          title: Text(displaySchool.isNotEmpty ? displaySchool : '학교 게시판',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          titleSpacing: hasMultiChild ? 0 : null,
          actions: [
            IconButton(icon: const Icon(Icons.search), onPressed: () => context.push('/search')),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(hasMultiChild ? 96 : 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 다자녀일 때 자녀 선택 탭
                if (hasMultiChild) _ChildSelectorTabs(
                  children: _children,
                  selectedIdx: _selectedChildIdx,
                  tabController: _childTabController!,
                  onChanged: (idx) {
                    setState(() {
                      _selectedChildIdx = idx;
                      // 학년 탭 리셋
                      if (tc.index != 0) tc.animateTo(0);
                    });
                  },
                ),
                TabBar(
                  controller: tc,
                  tabs: [
                    const Tab(text: '학교 전체'),
                    Tab(text: '$displayGrade학년'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          controller: tc,
          children: [
            PostListWidget(boardType: 'school', childId: selectedChildId),
            PostListWidget(boardType: 'grade', childId: selectedChildId),
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

    // lurker (로그인 O, 인증 X): 미리보기 + 읽기 1회 제한
    if (_isLurker) {
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
          onTap: _onLurkerTap,
          onCertify: () => context.go('/auth/school-select'),
          lurkerReadsLeft: 1 - _lurkerReads,
        ),
      );
    }

    // 비로그인 미리보기
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
        lurkerReadsLeft: null,
      ),
    );
  }
}

class _SchoolPreviewBoard extends StatelessWidget {
  final List<Map<String, dynamic>> posts;
  final Future<void> Function(int postId) onTap;
  final VoidCallback onCertify;
  final int? lurkerReadsLeft; // null = 비로그인, 0 이하 = 더 이상 읽기 불가

  const _SchoolPreviewBoard({
    required this.posts,
    required this.onTap,
    required this.onCertify,
    required this.lurkerReadsLeft,
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
                lurkerReadsLeft != null
                    ? (lurkerReadsLeft! > 0
                        ? '게시글 1개 읽기 가능 · 이후 학부모 인증이 필요합니다'
                        : '읽기 횟수를 모두 사용했습니다 · 학부모 인증 후 이용하세요')
                    : '학교 게시판 인기글 미리보기 · 학부모 인증 후 모든 글을 볼 수 있어요',
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

// ── 다자녀 선택 탭 바 ────────────────────────────────────

class _ChildSelectorTabs extends StatelessWidget {
  final List<Map<String, dynamic>> children;
  final int selectedIdx;
  final TabController tabController;
  final void Function(int) onChanged;

  const _ChildSelectorTabs({
    required this.children,
    required this.selectedIdx,
    required this.tabController,
    required this.onChanged,
  });

  String _schoolTypeLabel(String? type) => switch (type) {
    'elementary' => '초',
    'middle' => '중',
    'high' => '고',
    _ => '',
  };

  Color _typeColor(String? type) => switch (type) {
    'elementary' => Colors.green,
    'middle' => Colors.blue,
    'high' => Colors.purple,
    _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      onTap: onChanged,
      indicatorSize: TabBarIndicatorSize.tab,
      tabs: children.map((child) {
        final idx = children.indexOf(child);
        final isSelected = idx == selectedIdx;
        final schoolName = child['school_name'] as String? ?? '학교';
        final grade = child['grade'] as int? ?? 1;
        final type = child['school_type'] as String?;
        final typeLabel = _schoolTypeLabel(type);
        final typeColor = _typeColor(type);

        return Tab(
          height: 44,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: isSelected ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(typeLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: typeColor)),
            ),
            const SizedBox(width: 6),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schoolName.length > 8 ? '${schoolName.substring(0, 7)}…' : schoolName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                Text('$grade학년',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ],
            ),
          ]),
        );
      }).toList(),
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
