import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/school_select_screen.dart';
import '../features/auth/screens/auth_pending_screen.dart';
import '../features/auth/screens/invite_join_screen.dart';
import '../features/board/screens/post_detail_screen.dart';
import '../features/board/screens/post_write_screen.dart';
import '../features/board/screens/region_board_screen.dart';
import '../features/board/screens/school_board_screen.dart';
import '../features/board/screens/hot_board_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/profile/screens/add_child_screen.dart';
import '../features/notifications/screens/notification_list_screen.dart';
import '../features/search/screens/search_screen.dart';
import '../features/dm/screens/dm_list_screen.dart';
import '../features/dm/screens/dm_chat_screen.dart';
import '../features/legal/screens/terms_screen.dart';
import '../features/legal/screens/privacy_screen.dart';
import '../features/academy/screens/academy_screen.dart';
import '../features/academy/screens/academy_detail_screen.dart';
import '../features/academy/screens/academy_review_write_screen.dart';
import '../features/academy/screens/academy_recommend_screen.dart';
import 'api_client.dart' show tokenStorageProvider;
import 'constants.dart';
import 'push_notifications.dart';
import 'push_target.dart';
import 'refresh_bus.dart';
import 'sw_notification_bridge.dart';
import 'update_checker.dart';
import '../features/admin/screens/admin_login_screen.dart';
import '../features/admin/screens/admin_home_screen.dart';

final _rootNavKey = GlobalKey<NavigatorState>();
final _shellNavKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavKey,
    initialLocation: '/region',
    redirect: (context, state) async {
      final loc = state.matchedLocation;
      if (loc.startsWith('/admin')) return null;
      // 지역·학교·학원 탭은 비회원 미리보기 허용 — 화면 내부에서 인증 처리
      if (loc == '/region' || loc == '/school' || loc == '/academy') return null;
      final storage = ref.read(tokenStorageProvider);
      final token = await storage.read(AppConstants.tokenKey);
      final isAuthRoute = loc.startsWith('/auth') || loc.startsWith('/invite');
      if (token == null && !isAuthRoute) return '/auth/login';
      return null;
    },
    routes: [
      // ── 관리자 ────────────────────────────────────────
      GoRoute(path: '/admin/login', builder: (ctx, s) => const AdminLoginScreen()),
      GoRoute(
        path: '/admin',
        redirect: (ctx, s) async {
          final storage = ProviderScope.containerOf(ctx).read(tokenStorageProvider);
          final token = await storage.read(AppConstants.tokenKey);
          if (token == null) return '/auth/login';
          return null;
        },
        builder: (ctx, s) => const AdminHomeScreen(),
      ),

      // /board → /region 하위 호환 리다이렉트 (구 라우트 참조 대비)
      GoRoute(path: '/board', redirect: (ctx, s) => '/region'),

      // ── 인증 ──────────────────────────────────────────
      GoRoute(path: '/auth/login', builder: (ctx, s) => const LoginScreen()),
      GoRoute(path: '/auth/school-select', builder: (ctx, s) => const SchoolSelectScreen()),
      GoRoute(path: '/auth/pending', builder: (ctx, s) => const AuthPendingScreen()),

      // 초대 링크 딥링크
      GoRoute(
        path: '/invite/:token',
        parentNavigatorKey: _rootNavKey,
        builder: (ctx, s) => InviteJoinScreen(token: s.pathParameters['token']!),
      ),

      // ── 게시판 관련 (Shell 밖) ─────────────────────────
      GoRoute(
        path: '/board/write',
        parentNavigatorKey: _rootNavKey,
        builder: (ctx, s) => PostWriteScreen(
          boardType: s.uri.queryParameters['board_type'] ?? 'free',
        ),
      ),
      GoRoute(
        path: '/board/:postId',
        parentNavigatorKey: _rootNavKey,
        builder: (ctx, s) => PostDetailScreen(
          postId: int.parse(s.pathParameters['postId']!),
          highlightCommentId: int.tryParse(s.uri.queryParameters['highlight_comment_id'] ?? ''),
        ),
      ),
      // 대화(DM) 기능은 하단 탭에서는 뺐지만(당분간 미사용) 라우트 자체는 남겨둔다.
      GoRoute(path: '/dm', parentNavigatorKey: _rootNavKey, builder: (ctx, s) => const DmListScreen()),
      GoRoute(
        path: '/dm/:convId',
        parentNavigatorKey: _rootNavKey,
        builder: (ctx, s) => DmChatScreen(
          convId: int.parse(s.pathParameters['convId']!),
          otherNickname: s.extra as String? ?? '대화',
        ),
      ),
      GoRoute(path: '/profile', parentNavigatorKey: _rootNavKey, builder: (ctx, s) => const ProfileScreen()),
      GoRoute(path: '/profile/add-child', parentNavigatorKey: _rootNavKey, builder: (ctx, s) => const AddChildScreen()),
      GoRoute(path: '/notifications', parentNavigatorKey: _rootNavKey, builder: (ctx, s) => const NotificationListScreen()),
      GoRoute(path: '/terms', parentNavigatorKey: _rootNavKey, builder: (ctx, s) => const TermsScreen()),
      GoRoute(path: '/privacy', parentNavigatorKey: _rootNavKey, builder: (ctx, s) => const PrivacyScreen()),
      GoRoute(path: '/search', parentNavigatorKey: _rootNavKey, builder: (ctx, s) => const SearchScreen()),

      // ── 학원 후기 (Shell 밖) ───────────────────────────
      GoRoute(
        path: '/academy/recommend',
        parentNavigatorKey: _rootNavKey,
        builder: (ctx, s) => const AcademyRecommendScreen(),
      ),
      GoRoute(
        path: '/academy/:id/review/write',
        parentNavigatorKey: _rootNavKey,
        builder: (ctx, s) => AcademyReviewWriteScreen(
          academyId: int.parse(s.pathParameters['id']!),
          editingReview: s.extra as Map<String, dynamic>?,
        ),
      ),
      GoRoute(
        path: '/academy/:id',
        parentNavigatorKey: _rootNavKey,
        builder: (ctx, s) => AcademyDetailScreen(academyId: int.parse(s.pathParameters['id']!)),
      ),

      // ── 바텀 네비 Shell (5탭) ────────────────────────────
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootNavKey,
        builder: (ctx, state, shell) => _MainShell(shell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellNavKey,
            routes: [GoRoute(path: '/region', builder: (ctx, s) => const RegionBoardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/school', builder: (ctx, s) => const SchoolBoardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/academy', builder: (ctx, s) => const AcademyScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/hot', builder: (ctx, s) => const HotBoardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/my', builder: (ctx, s) => const ProfileScreen())],
          ),
        ],
      ),
    ],
  );
});


class _MainShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;
  const _MainShell({required this.shell});

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> with WidgetsBindingObserver {
  bool _showPushBanner = false;
  bool _pushRequesting = false;
  bool _showUpdateBanner = false;
  String? _initialBuildId;
  Timer? _updateCheckTimer;

  // 알림 배너 — 여러 알림이 짧은 시간에 연달아 오면 배너를 계속 새 내용으로
  // 갈아치우기만 해서 앞의 알림을 놓치기 쉬웠다. 배너가 떠 있는 동안 도착한
  // 건수를 세어, 1건이면 그 알림으로 바로 이동하는 기존 방식을 유지하고
  // 2건 이상이면 "새 알림 N건" + "전체 보기"(알림함)로 전환해 화면을 계속
  // 가리지 않으면서도 놓치는 알림이 없게 한다.
  int _pendingNotifCount = 0;
  String? _pendingNotifText;
  String? _pendingNotifLocation;
  Timer? _bannerDismissTimer;
  StreamSubscription<String>? _swClickSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPush();
    _initUpdateCheck();
  }

  @override
  void dispose() {
    _swClickSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _updateCheckTimer?.cancel();
    _bannerDismissTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 탭을 다른 데 갔다가 돌아왔을 때(브라우저 탭 전환 등)도 확인 —
    // 배포 직후부터 다음 정기 체크까지 기다리지 않아도 되게 함.
    if (state == AppLifecycleState.resumed) _checkForUpdate();
  }

  /// Flutter Web은 브라우저/서비스워커 캐싱 때문에 배포해도 새로고침 전까지
  /// 예전 화면이 계속 보일 수 있다 — 관리자 화면 버튼이 안 보인다는 리포트의
  /// 원인이었다. 배포 시 CI가 새로 심는 build-id와 지금 로드된 페이지의
  /// build-id를 주기적으로 비교해, 새 배포가 감지되면 새로고침을 안내한다.
  void _initUpdateCheck() {
    _initialBuildId = currentBuildId();
    if (_initialBuildId == null) return; // 웹이 아니거나 메타 태그 없음 — 기능 비활성
    _updateCheckTimer = Timer.periodic(const Duration(minutes: 15), (_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    if (_initialBuildId == null || _showUpdateBanner) return;
    final latest = await fetchLatestBuildId();
    if (latest != null && latest != _initialBuildId && mounted) {
      setState(() => _showUpdateBanner = true);
    }
  }

  Future<void> _initPush() async {
    // 재방문 시 이미 허용된 상태면 조용히 토큰만 최신화, 아직 결정 안 됐으면 배너 노출.
    await PushNotifications.silentlyRegisterIfAlreadyAllowed(ref);
    final show = await PushNotifications.shouldShowBanner();
    if (mounted) setState(() => _showPushBanner = show);
    PushNotifications.listenForegroundMessages((msg) {
      if (!mounted) return;
      final title = msg.notification?.title ?? 'MomsTalk';
      final body = msg.notification?.body ?? '';
      final location = pushTargetLocation(msg.data);
      _showNotificationBanner(title: title, body: body, location: location);
    });

    // 상단바 알림을 탭해서 앱이 열린 경우(백그라운드에서 복귀 / 종료 상태에서
    // 콜드스타트) — 포그라운드 배너와 달리 OS가 알림을 이미 보여줬으므로,
    // 여기서는 배너 없이 바로 해당 화면으로 이동한다. (네이티브 앱 빌드용 —
    // 지금은 모바일도 웹으로 접속 중이라 바로 아래 서비스워커 브리지가 실제로 쓰인다.)
    PushNotifications.listenBackgroundTaps(_navigateFromPush);
    final initialMessage = await PushNotifications.getInitialMessage();
    if (initialMessage != null) _navigateFromPush(initialMessage);

    // 웹(PWA 포함): 알림을 탭했을 때 이미 열려있는 탭/창이 있으면 서비스워커가
    // 그 탭을 포커스만 시키고 실제 이동은 postMessage로 알려준다 — 이걸 듣는
    // 코드가 없어서 "알림을 눌러도 게시글로 안 열린다"는 신고의 실제 원인이었다.
    // path는 '/#/board/123' 형태(해시 라우팅)라 앞의 '#'을 떼고 push한다.
    _swClickSub = notificationClickPaths().listen((path) {
      if (!mounted) return;
      final location = path.startsWith('/#') ? path.substring(2) : path;
      if (location.isNotEmpty) context.push(location);
    });
  }

  void _navigateFromPush(RemoteMessage msg) {
    final location = pushTargetLocation(msg.data);
    if (location != null && mounted) context.push(location);
  }

  /// 알림함으로 가는 상시 버튼 대신, 알림이 실제로 도착한 순간에만 화면
  /// 상단에 배너로 보여준다 — Flutter 자체 위젯(MaterialBanner)이라
  /// 브라우저/기기 종류와 무관하게 항상 동작한다(OS 푸시와 별개로, 앱을
  /// 보고 있는 동안 도착한 알림을 놓치지 않게 하는 용도).
  void _showNotificationBanner({required String title, required String body, String? location}) {
    _pendingNotifCount++;
    if (_pendingNotifCount == 1) {
      // 배너가 새로 뜨는(또는 직전에 완전히 닫혔던) 첫 알림일 때만 구체적인
      // 제목/내용과 이동 위치를 기억해둔다 — 2건째부터는 "N건" 요약으로
      // 바뀌므로 어차피 이 값은 쓰이지 않는다.
      _pendingNotifText = body.isEmpty ? title : '$title — $body';
      _pendingNotifLocation = location;
    }
    _renderNotificationBanner();
    _bannerDismissTimer?.cancel();
    _bannerDismissTimer = Timer(const Duration(seconds: 6), _dismissNotificationBanner);
  }

  void _renderNotificationBanner() {
    final messenger = ScaffoldMessenger.of(context);
    final multiple = _pendingNotifCount > 1;
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.notifications_active, color: Color(0xFF4A90D9)),
        content: Text(
          multiple ? '새 알림이 $_pendingNotifCount건 있어요' : (_pendingNotifText ?? ''),
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          if (multiple)
            TextButton(
              onPressed: () {
                _dismissNotificationBanner();
                context.push('/notifications');
              },
              child: const Text('전체 보기'),
            )
          else if (_pendingNotifLocation != null)
            TextButton(
              onPressed: () {
                _dismissNotificationBanner();
                context.push(_pendingNotifLocation!);
              },
              child: const Text('보기'),
            ),
          TextButton(
            onPressed: _dismissNotificationBanner,
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  void _dismissNotificationBanner() {
    if (mounted) ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    _pendingNotifCount = 0;
    _pendingNotifText = null;
    _pendingNotifLocation = null;
    _bannerDismissTimer?.cancel();
  }

  Future<void> _enablePush() async {
    setState(() => _pushRequesting = true);
    final ok = await PushNotifications.requestAndRegister(ref);
    if (mounted) {
      setState(() { _showPushBanner = false; _pushRequesting = false; });
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('알림이 차단되었습니다. 브라우저 설정에서 다시 허용할 수 있어요.')),
        );
      }
    }
    await PushNotifications.dismissBanner();
  }

  Future<void> _dismissPushBanner() async {
    setState(() => _showPushBanner = false);
    await PushNotifications.dismissBanner();
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    return Scaffold(
      body: Column(
        children: [
          if (_showUpdateBanner) _UpdateAvailableBanner(onReload: reloadPage),
          if (_showPushBanner) _PushPermissionBanner(
            requesting: _pushRequesting,
            onEnable: _enablePush,
            onDismiss: _dismissPushBanner,
          ),
          Expanded(child: shell),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) {
          // 이미 선택된 탭을 다시 탭하면 해당 탭 내부 화면을 새로고침한다.
          if (i == shell.currentIndex) bumpBoardRefresh(ref);
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.location_on_outlined), selectedIcon: Icon(Icons.location_on), label: '지역'),
          NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: '학교'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: '학원'),
          NavigationDestination(icon: Icon(Icons.local_fire_department_outlined), selectedIcon: Icon(Icons.local_fire_department), label: '인기'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '내정보'),
        ],
      ),
    );
  }
}

// ── 새 버전 배포 안내 배너 ────────────────────────────────────────
// 캐싱 때문에 새로고침 전까지 예전 화면이 계속 보이는 문제 대응 —
// _MainShellState._checkForUpdate()가 새 build-id를 감지하면 노출된다.
// 무시하고 계속 쓸 수도 있지만(닫기 없음, 배포마다 계속 최신화 필요하니
// 눈에 계속 띄게 둠), 새로고침 버튼을 누르면 바로 최신 빌드로 전환된다.
class _UpdateAvailableBanner extends StatelessWidget {
  final VoidCallback onReload;
  const _UpdateAvailableBanner({required this.onReload});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade600,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            const Icon(Icons.system_update_alt, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('새 버전이 있어요! 새로고침하면 최신 기능을 바로 이용할 수 있어요.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
            TextButton(
              onPressed: onReload,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.orange.shade700,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('새로고침', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── 웹 푸시 권한 유도 배너 ────────────────────────────────────────
// 진입 즉시 브라우저 권한 팝업을 띄우면 대부분 거절당하고(한 번 거절되면
// 사용자가 직접 브라우저 설정을 풀기 전까지 재요청 불가), 사용자가 이 배너를
// 눌렀을 때만 권한 팝업이 뜨도록 유도한다.
class _PushPermissionBanner extends StatelessWidget {
  final bool requesting;
  final VoidCallback onEnable;
  final VoidCallback onDismiss;
  const _PushPermissionBanner({required this.requesting, required this.onEnable, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            const Icon(Icons.notifications_active_outlined, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('새 댓글이나 좋아요 알림을 받아보세요!', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: requesting ? null : onEnable,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
              child: requesting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('알림 켜기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: requesting ? null : onDismiss,
            ),
          ]),
        ),
      ),
    );
  }
}
