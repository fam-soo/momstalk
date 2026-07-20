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
/// (rootNavigatorKey) 스택에 쌓인 상태라 shell.currentIndex를 못 쓴다.
/// /academy/*, /notifications, /dm, /profile처럼 그 자체로 소속 탭이
/// 분명한 경로는 경로로 바로 판단하고, /board/*(게시글 상세·글쓰기)처럼
/// 여러 탭(지역/학교/학년/전체)에서 공통으로 올 수 있는 경로는 경로만으로
/// 알 수 없어 lastActiveTabIndexProvider(셸이 마지막으로 기록한 활성 탭)를
/// 그대로 따른다 — 예전엔 이 경우 무조건 지역 탭으로 표시돼, 학교/인기
/// 탭에서 글쓰기·게시글 상세로 들어가면 하단 네비가 지역으로 바뀐 것처럼
/// 보이는 버그가 있었다.
class MainBottomNav extends ConsumerWidget {
  const MainBottomNav({super.key});

  static const _tabPaths = ['/region', '/school', '/academy', '/hot', '/my'];

  int? _confidentTabIndex(String location) {
    if (location.startsWith('/academy')) return 2;
    if (location.startsWith('/profile') ||
        location.startsWith('/my') ||
        location.startsWith('/notifications') ||
        location.startsWith('/dm')) {
      return 4;
    }
    return null;
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
    final int selectedIndex = _confidentTabIndex(location) ?? ref.watch(lastActiveTabIndexProvider);

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
