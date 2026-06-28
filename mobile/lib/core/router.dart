import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/school_select_screen.dart';
import '../features/auth/screens/auth_pending_screen.dart';
import '../features/auth/screens/invite_join_screen.dart';
import '../features/board/screens/board_screen.dart';
import '../features/board/screens/post_detail_screen.dart';
import '../features/board/screens/post_write_screen.dart';
import '../features/board/screens/region_board_screen.dart';
import '../features/board/screens/school_board_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/search/screens/search_screen.dart';
import '../features/dm/screens/dm_list_screen.dart';
import '../features/dm/screens/dm_chat_screen.dart';
import '../features/legal/screens/terms_screen.dart';
import '../features/legal/screens/privacy_screen.dart';
import '../features/academy/screens/academy_screen.dart';
import '../features/academy/screens/academy_detail_screen.dart';
import '../features/academy/screens/academy_review_write_screen.dart';
import 'api_client.dart' show tokenStorageProvider;
import 'constants.dart';
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
        builder: (ctx, s) => PostDetailScreen(postId: int.parse(s.pathParameters['postId']!)),
      ),
      GoRoute(
        path: '/dm/:convId',
        parentNavigatorKey: _rootNavKey,
        builder: (ctx, s) => DmChatScreen(
          convId: int.parse(s.pathParameters['convId']!),
          otherNickname: s.extra as String? ?? '대화',
        ),
      ),
      GoRoute(path: '/profile', parentNavigatorKey: _rootNavKey, builder: (ctx, s) => const ProfileScreen()),
      GoRoute(path: '/terms', parentNavigatorKey: _rootNavKey, builder: (ctx, s) => const TermsScreen()),
      GoRoute(path: '/privacy', parentNavigatorKey: _rootNavKey, builder: (ctx, s) => const PrivacyScreen()),
      GoRoute(path: '/search', parentNavigatorKey: _rootNavKey, builder: (ctx, s) => const SearchScreen()),

      // ── 학원 후기 (Shell 밖) ───────────────────────────
      GoRoute(
        path: '/academy/:id/review/write',
        parentNavigatorKey: _rootNavKey,
        builder: (ctx, s) => AcademyReviewWriteScreen(academyId: int.parse(s.pathParameters['id']!)),
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
            routes: [GoRoute(path: '/dm', builder: (ctx, s) => const DmListScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/my', builder: (ctx, s) => const ProfileScreen())],
          ),
        ],
      ),
    ],
  );
});

class _MainShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const _MainShell({required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.location_on_outlined), selectedIcon: Icon(Icons.location_on), label: '지역'),
          NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: '학교'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: '학원'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: '대화'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '내정보'),
        ],
      ),
    );
  }
}
