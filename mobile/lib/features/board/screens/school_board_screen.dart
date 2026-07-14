import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../../../core/constants.dart';
import '../../../core/kst_time.dart';
import '../../../core/notification_bell.dart';
import '../../../core/school_display.dart';
import '../../../core/unified_notify_button.dart';
import '../../../core/refresh_bus.dart';
import 'post_list_widget.dart';

class SchoolBoardScreen extends ConsumerStatefulWidget {
  const SchoolBoardScreen({super.key});

  @override
  ConsumerState<SchoolBoardScreen> createState() => _SchoolBoardScreenState();
}

class _SchoolBoardScreenState extends ConsumerState<SchoolBoardScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _loading = true;
  bool _isMember = false;
  bool _isLurker = false; // 로그인 했지만 미인증
  String _schoolName = '';
  int? _grade; // null이면 학년 미선택 — 학년 탭을 잠근다
  List<Map<String, dynamic>> _previewPosts = [];
  int _previewTaps = 0;
  int _lurkerReads = 0; // lurker 읽기 횟수 (계정당 1회, 초기화 없음)
  TabController? _tabController;
  List<Map<String, dynamic>> _children = [];
  int _selectedChildIdx = 0;
  bool _authPending = false;
  bool _isAdmin = false;
  // 학교 게시판 언락(같은 학교 정회원 N명 모임) 상태
  bool _schoolLocked = false;
  int _schoolMemberCount = 0;
  int _schoolThreshold = 10;
  int _schoolRemaining = 10;
  // 잠금 화면에서 "우리 학교도 모으면 열린다"는 경쟁심을 자극하기 위한
  // 이미 열린 학교 현황(개수 + 인원 상위 학교 목록, 익명 집계).
  Map<String, dynamic>? _leaderboard;
  static const _tapLimit = 2;
  static const _prefKey = 'preview_taps_school';
  static const _lurkerReadKey = 'school_lurker_reads';
  Timer? _unlockPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unlockPollTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 잠금 화면을 보고 있다가 앱으로 돌아오면 그 사이 학교 인원이 늘었을 수
    // 있으니 즉시 최신 현황을 반영한다.
    if (state == AppLifecycleState.resumed && _schoolLocked && !_isAdmin) {
      _loadUnlockStatus(_children.isNotEmpty && _selectedChildIdx < _children.length
          ? _children[_selectedChildIdx]['school_code'] as String?
          : null);
    }
  }

  /// 잠금 화면을 보는 동안 실시간에 가깝게 인원 현황이 갱신되도록 주기적으로
  /// 폴링한다. 잠금이 풀리거나 화면을 벗어나면 스스로 멈춘다.
  void _ensureUnlockPolling() {
    if (_unlockPollTimer != null || !_schoolLocked || _isAdmin) return;
    _unlockPollTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!mounted || !_schoolLocked) {
        _unlockPollTimer?.cancel();
        _unlockPollTimer = null;
        return;
      }
      final schoolCode = _children.isNotEmpty && _selectedChildIdx < _children.length
          ? _children[_selectedChildIdx]['school_code'] as String?
          : null;
      await _loadUnlockStatus(schoolCode);
    });
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
      final authPending = profile['auth_pending'] as bool? ?? false;
      if (mounted) {
        final children = (profile['children'] as List? ?? [])
            .map((c) => Map<String, dynamic>.from(c as Map))
            .toList();
        final canAccess = (isMember || isAdmin) && !authPending;
        final tabs = canAccess ? TabController(length: 2, vsync: this) : null;
        // 내정보(활성 자녀)를 기준으로 초기 선택 자녀를 맞춘다 — 항상 0번째로
        // 고정하면 학교 게시판이 내정보에서 고른 자녀와 무관하게 보였다.
        final activeChildId = profile['active_child_id'] as int?;
        final activeIdx = activeChildId == null
            ? 0
            : children.indexWhere((c) => c['id'] == activeChildId);
        final resolvedIdx = activeIdx >= 0 ? activeIdx : 0;

        // 언락 여부를 먼저 확정한 뒤에 _loading을 내려야 한다. 순서를 바꾸면
        // "정회원 접근 가능" 화면이 잠금 여부를 모르는 채로 먼저 그려지고,
        // 그 사이에 PostListWidget이 곧바로 /posts를 호출해 서버의 잠금
        // 가드(403)를 그대로(가공되지 않은 에러 문구로) 노출하는 문제가 있었다.
        var schoolLocked = false;
        var memberCount = 0;
        var threshold = _schoolThreshold;
        var remaining = _schoolThreshold;
        if (canAccess && !isAdmin) {
          final schoolCode = children.isNotEmpty && resolvedIdx < children.length
              ? children[resolvedIdx]['school_code'] as String?
              : null;
          final unlock = await _fetchUnlockStatus(schoolCode);
          if (unlock != null) {
            schoolLocked = !(unlock['unlocked'] as bool? ?? true);
            memberCount = unlock['member_count'] as int? ?? 0;
            threshold = unlock['threshold'] as int? ?? threshold;
            remaining = unlock['remaining'] as int? ?? 0;
          }
        }

        if (!mounted) return;
        setState(() {
          _isMember = canAccess;
          // auth_pending 중이면 lurker도 아닌 '인증 대기' 상태로 처리
          _isLurker = !canAccess && !authPending;
          _authPending = authPending && !isAdmin;
          _isAdmin = isAdmin;
          _schoolName = profile['school_name'] as String? ?? '';
          _grade = profile['grade'] as int?;
          _children = children;
          _selectedChildIdx = resolvedIdx;
          _tabController = tabs;
          _schoolLocked = schoolLocked;
          _schoolMemberCount = memberCount;
          _schoolThreshold = threshold;
          _schoolRemaining = remaining;
          _loading = false;
        });
        if (schoolLocked) {
          _ensureUnlockPolling();
          _loadLeaderboard();
        }
      }
    } catch (_) {
      await _loadPreview();
    }
  }

  /// 학교 게시판 언락 현황 조회 — 지역/학원과 달리 학교 게시판만 같은 학교
  /// 정회원이 일정 인원 모여야 열린다. 조회 실패 시 null(잠그지 않음 — 서버
  /// 오류로 접근을 막지 않기 위함).
  Future<Map<String, dynamic>?> _fetchUnlockStatus(String? schoolCode) async {
    if (schoolCode == null || schoolCode.isEmpty) return null;
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/schools/$schoolCode/unlock-status');
      return Map<String, dynamic>.from(resp.data as Map);
    } catch (_) {
      return null;
    }
  }

  /// 이미 열린 학교 수 + 인원 상위 학교 목록. 잠금 화면에 "우리 학교도
  /// 모으면 열린다"는 경쟁심을 자극하는 요소로 노출한다.
  Future<void> _loadLeaderboard() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/schools/unlock-leaderboard');
      if (mounted) setState(() => _leaderboard = Map<String, dynamic>.from(resp.data as Map));
    } catch (_) {}
  }

  Future<void> _loadUnlockStatus(String? schoolCode) async {
    final data = await _fetchUnlockStatus(schoolCode);
    if (!mounted) return;
    setState(() {
      _schoolLocked = data == null ? false : !(data['unlocked'] as bool? ?? true);
      _schoolMemberCount = data?['member_count'] as int? ?? 0;
      _schoolThreshold = data?['threshold'] as int? ?? _schoolThreshold;
      _schoolRemaining = data?['remaining'] as int? ?? 0;
    });
    if (_schoolLocked) {
      _ensureUnlockPolling();
      _loadLeaderboard();
    } else {
      _unlockPollTimer?.cancel();
      _unlockPollTimer = null;
    }
  }

  /// 학교 게시판에서 자녀를 바꾸면 내정보(active_child)에도 반영하고,
  /// 지역/학원 탭 등 다른 화면도 함께 새로고침되도록 신호를 보낸다.
  Future<void> _onSelectChild(int idx, TabController tc) async {
    if (idx == _selectedChildIdx) return;
    final childId = _children[idx]['id'] as int?;
    setState(() {
      _selectedChildIdx = idx;
      if (tc.index != 0) tc.animateTo(0);
    });
    if (!_isAdmin) await _loadUnlockStatus(_children[idx]['school_code'] as String?);
    if (childId == null) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/auth/me/active-child/$childId');
      bumpBoardRefresh(ref);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('자녀 전환 실패: $e')));
    }
  }

  /// 언락 안내 화면의 "초대하기" — 초대 링크를 발급해 클립보드에 복사한다.
  Future<void> _shareInvite() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/auth/invite/generate');
      final deeplink = resp.data['deeplink'] as String? ?? '';
      if (deeplink.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: deeplink));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('초대 링크가 복사됐어요! 카카오톡 등에 붙여넣어 같은 학교 학부모를 초대해보세요.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('초대 링크 생성 실패: $e')));
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
    // 자녀 추가/학교 변경 후 이 화면으로 돌아오거나, 이미 선택된 탭을 다시
    // 탭했을 때 학교/학년/자녀 목록을 다시 불러온다.
    ref.listen<int>(boardRefreshSignal, (prev, next) {
      if (prev != null && prev != next) _init();
    });
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // 인증 사진 심사 대기 중
    if (_authPending) {
      return Scaffold(
        appBar: AppBar(
          leading: const NotificationBellButton(),
          centerTitle: true,
          title: const Text('학교 게시판', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.hourglass_top_rounded, size: 64, color: Colors.orange.shade400),
              const SizedBox(height: 20),
              const Text('학부모 인증 심사 중', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(
                '알림장 캡처 사진을 검토하고 있습니다.\n관리자 승인 후 학교 게시판을 이용하실 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.6, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => context.go('/auth/pending'),
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('인증 상태 확인'),
              ),
            ]),
          ),
        ),
      );
    }

    if (_isMember) {
      final tc = _tabController!;
      final hasMultiChild = _children.length > 1;
      final selChild = hasMultiChild && _selectedChildIdx < _children.length
          ? _children[_selectedChildIdx]
          : null;
      final displaySchool = selChild != null
          ? (selChild['school_name'] as String? ?? _schoolName)
          : _schoolName;
      final displayGrade = selChild != null
          ? selChild['grade'] as int?
          : _grade;
      final hasGrade = displayGrade != null;
      final selectedChildId = selChild?['id'] as int?;
      final appBarTitle = hasMultiChild
          ? _SchoolDropdownTitle(
              children: _children,
              selectedIdx: _selectedChildIdx,
              onChanged: (idx) => _onSelectChild(idx, tc),
            )
          : Text(displaySchool.isNotEmpty ? displaySchool : '학교 게시판',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15));

      // 같은 학교 정회원이 기준 인원 미만이면 게시판 대신 언락 안내를 보여준다.
      if (_schoolLocked) {
        return Scaffold(
          appBar: AppBar(
            leading: const NotificationBellButton(),
            centerTitle: true,
            title: appBarTitle,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '인원 현황 새로고침',
                onPressed: () => _loadUnlockStatus(selChild?['school_code'] as String?),
              ),
            ],
          ),
          body: _SchoolLockedView(
            schoolName: displaySchool,
            memberCount: _schoolMemberCount,
            threshold: _schoolThreshold,
            remaining: _schoolRemaining,
            onInvite: _shareInvite,
            leaderboard: _leaderboard,
          ),
        );
      }

      return Scaffold(
        appBar: AppBar(
          // 학교 게시판은 탭이 학교/학년 둘이라, 현재 선택된 탭 기준으로
          // 알림 버튼이 대상 게시판을 자동으로 바꿔가며 표시한다.
          leading: AnimatedBuilder(
            animation: tc,
            builder: (_, __) => tc.index == 1 && hasGrade
                ? const UnifiedNotifyButton(prefKey: 'notify_grade', label: '학년')
                : const UnifiedNotifyButton(prefKey: 'notify_school', label: '학교'),
          ),
          centerTitle: true,
          title: appBarTitle,
          actions: [
            IconButton(icon: const Icon(Icons.search), onPressed: () => context.push('/search')),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: TabBar(
              controller: tc,
              onTap: (i) {
                if (i == 1 && !hasGrade) {
                  tc.animateTo(0);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('학년이 등록되어 있지 않아요. 내정보에서 학년을 선택해주세요.'),
                    action: SnackBarAction(label: '내정보로', onPressed: () => context.go('/my')),
                  ));
                }
              },
              tabs: [
                const Tab(text: '학교 전체'),
                Tab(
                  child: hasGrade
                      ? Text('$displayGrade학년')
                      : Row(mainAxisSize: MainAxisSize.min, children: const [
                          Icon(Icons.lock_outline, size: 14),
                          SizedBox(width: 4),
                          Text('학년 미선택'),
                        ]),
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          controller: tc,
          // 학교/자녀 변경 시 새로 마운트되도록 식별값을 key에 반영 (board_screen.dart와 동일한 이유)
          children: [
            PostListWidget(
              key: ValueKey('school-$displaySchool-$displayGrade-$selectedChildId'),
              boardType: 'school',
              childId: selectedChildId,
            ),
            if (hasGrade)
              PostListWidget(
                key: ValueKey('grade-$displaySchool-$displayGrade-$selectedChildId'),
                boardType: 'grade',
                childId: selectedChildId,
              )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_outline, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text('학년 정보가 없어 학년 게시판을 이용할 수 없어요.\n내정보에서 학년을 선택해주세요.',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: () => context.go('/my'), child: const Text('내정보로 이동')),
                  ]),
                ),
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            final boardType = tc.index == 1 && hasGrade ? 'grade' : 'school';
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
          leading: const NotificationBellButton(),
          centerTitle: true,
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
        leading: const NotificationBellButton(),
        centerTitle: true,
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

// ── 학교 게시판 언락 안내 (같은 학교 정회원 N명 모임 전) ──────────────
class _SchoolLockedView extends StatelessWidget {
  final String schoolName;
  final int memberCount;
  final int threshold;
  final int remaining;
  final VoidCallback onInvite;
  final Map<String, dynamic>? leaderboard;

  const _SchoolLockedView({
    required this.schoolName,
    required this.memberCount,
    required this.threshold,
    required this.remaining,
    required this.onInvite,
    this.leaderboard,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = threshold == 0 ? 0.0 : (memberCount / threshold).clamp(0.0, 1.0);
    final unlockedCount = leaderboard?['unlocked_school_count'] as int? ?? 0;
    final topSchools = (leaderboard?['top_schools'] as List?)?.cast<Map>() ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            schoolName.isNotEmpty ? '$schoolName 게시판, 곧 열려요!' : '학교 게시판, 곧 열려요!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '같은 학교 학부모가 모이면 자동으로 열려요.\n지금 $memberCount명 모였고, $remaining명 더 모이면 이용할 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
            ),
          ),
          const SizedBox(height: 6),
          Text('$memberCount / $threshold명', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onInvite,
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('같은 학교 학부모 초대하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          const SizedBox(height: 8),
          Text('지역·학원 게시판은 지금 바로 이용할 수 있어요',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          if (leaderboard != null) ...[
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 16),
            topSchools.isNotEmpty
                ? _SchoolUnlockLeaderboard(unlockedCount: unlockedCount, topSchools: topSchools)
                : _FirstToOpenBanner(schoolName: schoolName),
          ],
        ],
      ),
    );
  }
}

/// 아직 어느 학교도 언락 기준을 못 넘긴 초기 단계(전체 서비스 기준)에는
/// 순위표 대신 "우리 학교가 최초 타이틀을 가져가자"는 메시지로 대체한다.
/// topSchools가 비어 있다고 이 섹션 자체를 숨기면 잠금 화면 하단이 다시
/// 텅 비어 보이는 문제가 있었다.
class _FirstToOpenBanner extends StatelessWidget {
  final String schoolName;
  const _FirstToOpenBanner({required this.schoolName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.15)),
      ),
      child: Column(children: [
        Icon(Icons.flag_outlined, size: 28, color: theme.colorScheme.primary),
        const SizedBox(height: 8),
        Text(
          '아직 열린 학교 게시판이 없어요!',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 4),
        Text(
          '${schoolName.isNotEmpty ? schoolName : '우리 학교'}가 맘스토크 최초로 게시판을 여는 학교가 되어보세요!\n학부모를 초대할수록 더 빨리 열려요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.5, color: Colors.grey.shade700),
        ),
      ]),
    );
  }
}

/// 잠금 화면 하단에 이미 열린 학교 현황을 보여줘 "우리 학교도 모으면
/// 열린다"는 경쟁심을 자극한다. 개인정보 없이 학교명·지역·인원수만 노출.
class _SchoolUnlockLeaderboard extends StatelessWidget {
  final int unlockedCount;
  final List<Map> topSchools;
  const _SchoolUnlockLeaderboard({required this.unlockedCount, required this.topSchools});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.emoji_events_outlined, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '이미 $unlockedCount개교 게시판이 열렸어요!',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        ...topSchools.asMap().entries.map((entry) {
          final rank = entry.key + 1;
          final s = entry.value;
          final name = s['school_name'] as String? ?? '';
          final region = s['region'] as String?;
          final count = s['member_count'] as int? ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(
                width: 20,
                child: Text('$rank', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
              ),
              Expanded(
                child: Text(
                  region != null && region.isNotEmpty ? '$region · $name' : name,
                  style: const TextStyle(fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('$count명', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
            ]),
          );
        }),
      ]),
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
    final kst = parseServerTimeToKst(iso);
    if (kst == null) return '';
    final nowKst = DateTime.now().toUtc().add(kstOffset);
    final diff = nowKst.difference(kst);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분';
    if (diff.inHours < 24) return '${diff.inHours}시간';
    return DateFormat('MM.dd').format(kst);
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

// ── 다자녀 학교 드롭다운 제목 ──────────────────────────────

class _SchoolDropdownTitle extends StatelessWidget {
  final List<Map<String, dynamic>> children;
  final int selectedIdx;
  final void Function(int) onChanged;

  const _SchoolDropdownTitle({
    required this.children,
    required this.selectedIdx,
    required this.onChanged,
  });

  String _typeLabel(String? type) => switch (type) {
    'elementary' => '초',
    'middle' => '중',
    'high' => '고',
    'preschool' => '미취학',
    _ => '',
  };

  Color _typeColor(String? type) => switch (type) {
    'elementary' => Colors.green,
    'middle' => Colors.blue,
    'high' => Colors.purple,
    'preschool' => Colors.orange,
    _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final sel = children[selectedIdx];
    final isPreschool = sel['school_type'] == 'preschool';
    final schoolName = isPreschool
        ? ((sel['region'] as String?)?.isNotEmpty == true ? sel['region'] as String : '미취학')
        : (sel['school_name'] as String? ?? '학교');
    final grade = sel['grade'] as int? ?? 1;
    final type = sel['school_type'] as String?;
    final typeLabel = _typeLabel(type);
    final typeColor = _typeColor(type);

    return PopupMenuButton<int>(
      onSelected: onChanged,
      tooltip: '학교 선택',
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => children.asMap().entries.map((entry) {
        final i = entry.key;
        final c = entry.value;
        final cIsPreschool = c['school_type'] == 'preschool';
        final cSchool = cIsPreschool
            ? ((c['region'] as String?)?.isNotEmpty == true ? c['region'] as String : '미취학')
            : (c['school_name'] as String? ?? '학교');
        final cGrade = c['grade'] as int? ?? 1;
        final cType = c['school_type'] as String?;
        final cLabel = _typeLabel(cType);
        final cColor = _typeColor(cType);
        return PopupMenuItem<int>(
          value: i,
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(cLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cColor)),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cIsPreschool ? cSchool : shortSchoolName(cSchool), style: TextStyle(
                fontWeight: i == selectedIdx ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              )),
              if (!cIsPreschool) Text('$cGrade학년', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
            if (i == selectedIdx) ...[
              const Spacer(),
              const Icon(Icons.check, size: 16, color: Colors.blue),
            ],
          ]),
        );
      }).toList(),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: typeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(typeLabel,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: typeColor)),
        ),
        const SizedBox(width: 8),
        Text(
          isPreschool ? schoolName : shortSchoolName(schoolName),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(width: 2),
        if (!isPreschool) Text(' $grade학년', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(width: 2),
        const Icon(Icons.arrow_drop_down, size: 20),
      ]),
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
