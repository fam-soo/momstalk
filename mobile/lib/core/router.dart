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
import '../features/profile/screens/profile_screen.dart';
import '../features/search/screens/search_screen.dart';
import '../features/dm/screens/dm_list_screen.dart';
import '../features/dm/screens/dm_chat_screen.dart';
import 'api_client.dart' show tokenStorageProvider;
import 'constants.dart';

final _rootNavKey = GlobalKey<NavigatorState>();
final _shellNavKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavKey,
    initialLocation: '/board',
    redirect: (context, state) async {
      final storage = ref.read(tokenStorageProvider);
      final token = await storage.read(AppConstants.tokenKey);
      final loc = state.matchedLocation;
      final isAuthRoute = loc.startsWith('/auth') || loc.startsWith('/invite');
      if (token == null && !isAuthRoute) return '/auth/login';
      return null;
    },
    routes: [
      // ── 인증 ──────────────────────────────────────────
      GoRoute(path: '/auth/login', builder: (ctx, s) => const LoginScreen()),
      GoRoute(path: '/auth/school-select', builder: (ctx, s) => const SchoolSelectScreen()),
      GoRoute(path: '/auth/pending', builder: (ctx, s) => const AuthPendingScreen()),

      // 초대 링크 딥링크: momstalk://invite/{token} → /invite/{token}
      GoRoute(
        path: '/invite/:token',
        parentNavigatorKey: _rootNavKey,
        builder: (ctx, s) => InviteJoinScreen(token: s.pathParameters['token']!),
      ),

      // ── 게시판 관련 (Shell 밖) ─────────────────────────
      // /board/write 반드시 /board/:postId 앞에 위치해야 함 (순서대로 매칭)
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

      // ── 바텀 네비 Shell ──────────────────────────────────
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootNavKey,
        builder: (ctx, state, shell) => _MainShell(shell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellNavKey,
            routes: [GoRoute(path: '/board', builder: (ctx, s) => const BoardScreen())],
          ),
          StatefulShellBranch(routes: [GoRoute(path: '/search', builder: (ctx, s) => const SearchScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/dm', builder: (ctx, s) => const DmListScreen())]),
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
          NavigationDestination(icon: Icon(Icons.article_outlined), selectedIcon: Icon(Icons.article), label: '게시판'),
          NavigationDestination(icon: Icon(Icons.search), selectedIcon: Icon(Icons.search), label: '검색'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: '대화'),
        ],
      ),
    );
  }
}
