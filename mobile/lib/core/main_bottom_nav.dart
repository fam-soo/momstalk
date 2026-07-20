import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'refresh_bus.dart';
import 'user_profile_provider.dart';

/// 게시글 상세/작성, 알림함, 학원 상세/후기 작성, 검색, DM 등 바텀 탭 밖에서
/// push된 화면에서도 하단 네비게이션을 동일하게 보여주기 위한 위젯.
/// (예전엔 이런 화면들만 하단 네비가 사라져 화면 간 통일성이 없었다.)
///
/// StatefulShellRoute 안의 탭(_MainShell)과 달리 이 화면들은 그 바깥
/// (rootNavigatorKey) 스택에 쌓인 상태라 shell.currentIndex를 못 쓴다 —
/// 대신 현재 경로로 대략적인 탭을 추정하고, 탭을 누르면 해당 탭 루트로
/// go()한다(이 화면들은 스택에서 빠지고 탭 화면이 앞에 온다).
class MainBottomNav extends ConsumerWidget {
  const MainBottomNav({super.key});

  static const _tabPaths = ['/region', '/school', '/academy', '/hot', '/my'];

  int _inferTabIndex(String location) {
    if (location.startsWith('/academy')) return 2;
    if (location.startsWith('/school')) return 1;
    if (location.startsWith('/hot')) return 3;
    if (location.startsWith('/profile') ||
        location.startsWith('/my') ||
        location.startsWith('/notifications') ||
        location.startsWith('/dm')) {
      return 4;
    }
    return 0;
  }

  bool _onlyPreschoolChildren(AsyncValue<Map<String, dynamic>> profileAsync) {
    final children = profileAsync.valueOrNull?['children'] as List?;
    if (children == null || children.isEmpty) return false;
    return children.every((c) => (c as Map)['school_type'] == 'preschool');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final schoolLocked = _onlyPreschoolChildren(profileAsync);
    final location = GoRouterState.of(context).uri.toString();
    final selectedIndex = _inferTabIndex(location);

    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) {
        if (i == 1 && schoolLocked) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('미취학 자녀만 있으면 학교 게시판을 이용할 수 없어요. 학교 인증 후 이용해보세요.')),
          );
          return;
        }
        if (i == selectedIndex) bumpBoardRefresh(ref);
        context.go(_tabPaths[i]);
      },
      destinations: [
        const NavigationDestination(icon: Icon(Icons.location_on_outlined), selectedIcon: Icon(Icons.location_on), label: '지역'),
        NavigationDestination(
          icon: Icon(schoolLocked ? Icons.lock_outline : Icons.school_outlined),
          selectedIcon: Icon(schoolLocked ? Icons.lock_outline : Icons.school),
          label: '학교',
        ),
        const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: '학원'),
        const NavigationDestination(icon: Icon(Icons.local_fire_department_outlined), selectedIcon: Icon(Icons.local_fire_department), label: '인기'),
        const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '내정보'),
      ],
    );
  }
}
