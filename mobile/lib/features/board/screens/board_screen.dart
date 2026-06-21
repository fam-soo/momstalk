import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import 'post_detail_screen.dart' show showReportDialog;

final userProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
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
      if (!_tabController.indexIsChanging) {
        setState(() => _currentTab = _tabController.index);
      }
    });
    _registerFcmToken();
  }

  Future<void> _registerFcmToken() async {
    try {
      final messaging = _tryGetMessaging();
      if (messaging == null) return;
      final token = await messaging.getToken();
      if (token == null || !mounted) return;
      final dio = ref.read(dioProvider);
      await dio.post('/auth/me/fcm-token', data: {'token': token});
    } catch (_) {}
  }

  dynamic _tryGetMessaging() {
    try {
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 탭 정의: (label, boardType, locked)
  // lurker: 전체만 열림, 지역/학교/학년 잠금
  // member: label에 실제 지역·학교·학년 표시, 모두 열림
  List<(String label, String boardType, bool locked)> _buildTabs(Map<String, dynamic> profile) {
    final isMember = (profile['member_grade'] as String? ?? 'lurker') == 'member';
    final region = profile['region'] as String? ?? '';
    final school = profile['school_name'] as String? ?? '';
    final grade = profile['grade'] as int? ?? 1;

    if (isMember) {
      return [
        ('전체', 'free', false),
        (region.isNotEmpty ? region : '지역', 'region', false),
        (school.isNotEmpty ? school : '학교', 'school', false),
        ('$grade학년', 'grade', false),
      ];
    }
    return [
      ('전체', 'free', false),
      ('지역', 'region', true),
      ('학교', 'school', true),
      ('학년', 'grade', true),
    ];
  }

  void _showAuthBottomSheet({bool isPending = false}) {
    if (isPending) {
      // 심사 중인 경우 → 심사 대기 화면으로 이동
      context.push('/auth/pending');
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AuthPromptSheet(
        onStart: () {
          Navigator.pop(ctx);
          context.push('/auth/school-select');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) {
        final isAuthError = err is DioException && err.response?.statusCode == 401;
        if (isAuthError) {
          WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/auth/login'));
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(body: Center(child: Text('오류: $err')));
      },
      data: (profile) {
        final tabs = _buildTabs(profile);
        final isMember = (profile['member_grade'] as String? ?? 'lurker') == 'member';
        final isPending = profile['auth_pending'] as bool? ?? false;

        return Scaffold(
          appBar: AppBar(
            title: const Text('MomsTalk', style: TextStyle(fontWeight: FontWeight.bold)),
            bottom: TabBar(
              controller: _tabController,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: tabs.map((t) {
                if (t.$3) {
                  return Tab(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(isPending ? Icons.hourglass_top_rounded : Icons.lock_outline, size: 13),
                      const SizedBox(width: 4),
                      Text(t.$1),
                    ]),
                  );
                }
                return Tab(text: t.$1);
              }).toList(),
              onTap: (index) {
                if (tabs[index].$3) {
                  _tabController.index = _currentTab;
                  _showAuthBottomSheet(isPending: isPending);
                }
              },
            ),
            actions: [
              if (!isMember)
                TextButton.icon(
                  onPressed: () => _showAuthBottomSheet(isPending: isPending),
                  icon: Icon(isPending ? Icons.hourglass_top_rounded : Icons.verified_outlined, size: 16),
                  label: Text(isPending ? '심사 중' : '인증'),
                  style: TextButton.styleFrom(
                    foregroundColor: isPending ? Colors.orange : Theme.of(context).colorScheme.primary,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.account_circle_outlined),
                tooltip: '내 정보',
                onPressed: () => context.push('/profile'),
              ),
            ],
          ),
          body: TabBarView(
            controller: _tabController,
            children: tabs.map((t) {
              if (t.$3) {
                return _LockedBoardPlaceholder(
                  isPending: isPending,
                  onCertify: () => _showAuthBottomSheet(isPending: isPending),
                );
              }
              return _PostList(boardType: t.$2);
            }).toList(),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              if (!isMember) {
                _showAuthBottomSheet(isPending: isPending);
                return;
              }
              context.push('/board/write?board_type=${tabs[_currentTab].$2}');
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('글쓰기'),
          ),
        );
      },
    );
  }
}

// ── 인증 유도 Bottom Sheet ─────────────────────────────

class _AuthPromptSheet extends StatelessWidget {
  final VoidCallback onStart;
  const _AuthPromptSheet({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.school_outlined, color: Theme.of(context).colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('내 지역과 학교 소식을 보려면', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(height: 2),
                    Text('학부모 인증이 필요해요!', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 20),
            const _BenefitRow(icon: Icons.location_on_outlined, text: '우리 지역 학부모들의 생생한 이야기'),
            const SizedBox(height: 10),
            const _BenefitRow(icon: Icons.school_outlined, text: '우리 학교 · 학년 전용 게시판'),
            const SizedBox(height: 10),
            const _BenefitRow(icon: Icons.edit_outlined, text: '글쓰기 · 댓글 · DM 전체 기능'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('학교 검색으로 인증 시작하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 10),
      Text(text, style: const TextStyle(fontSize: 13)),
    ]);
  }
}

// ── 잠긴 게시판 플레이스홀더 ─────────────────────────

class _LockedBoardPlaceholder extends StatelessWidget {
  final VoidCallback onCertify;
  final bool isPending;
  const _LockedBoardPlaceholder({required this.onCertify, required this.isPending});

  @override
  Widget build(BuildContext context) {
    if (isPending) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_top_rounded, size: 56, color: Colors.orange.shade300),
              const SizedBox(height: 16),
              const Text('심사 진행 중', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '알림장 캡처를 검토하고 있어요.\n승인되면 이 게시판을 이용할 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.5),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onCertify,
                icon: const Icon(Icons.hourglass_top_rounded),
                label: const Text('심사 현황 확인'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('학부모 인증 후 이용 가능', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '내 지역 · 학교 · 학년 게시판은\n학부모 인증을 완료해야 열립니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCertify,
              icon: const Icon(Icons.search),
              label: const Text('학교 검색으로 인증하기'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 게시글 목록 ──────────────────────────────────────

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
          const Text('아직 게시글이 없어요.\n첫 번째 글을 남겨보세요!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _posts.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) => _PostCard(post: _posts[i], onRefresh: _load),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onRefresh;
  const _PostCard({required this.post, required this.onRefresh});

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

  void _showOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _PostActionSheet(post: post, ref: ref, onRefresh: onRefresh),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (ctx, ref, _) {
      final isPinned = post['is_pinned'] == true;
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
                  post['is_anonymous'] == true ? '익명' : '작성자',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
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
                if (isPinned) Container(
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
                Wrap(spacing: 4, children: tags.map((t) => Text('@${t.split(':').last}', style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.primary))).toList()),
              ],
              const SizedBox(height: 10),
              Row(children: [
                _Stat(icon: Icons.favorite_outline, value: post['like_count'] ?? 0),
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
  const _Stat({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: Colors.grey[500]),
      const SizedBox(width: 3),
      Text('$value', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
    ]);
  }
}

// ── 게시글 액션 시트 ─────────────────────────────────

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
