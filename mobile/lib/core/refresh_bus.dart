import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 게시판/프로필 화면들이 공통으로 구독하는 새로고침 신호.
///
/// 값을 증가(bump)시키면 이를 구독 중인 화면들이 데이터를 다시 불러온다.
/// go_router의 StatefulShellRoute(IndexedStack)는 탭을 벗어나도 화면의
/// State를 그대로 유지하기 때문에, 게시글 작성/자녀 추가/학교 변경처럼
/// 다른 화면에서 데이터를 바꾸고 돌아왔을 때 목록 화면이 자동으로 다시
/// 불러오지 않는다. 이 신호를 통해 "돌아왔을 때 최신 상태로 갱신"을
/// 명시적으로 트리거한다. 또한 이미 선택된 하단 탭을 다시 탭했을 때도
/// 같은 신호로 새로고침을 요청한다.
final boardRefreshSignal = StateProvider<int>((_) => 0);

void bumpBoardRefresh(WidgetRef ref) {
  ref.read(boardRefreshSignal.notifier).state++;
}

/// 관리자 패널 전용 새로고침 신호. 관리자 패널은 각 탭(Pane)이
/// AutomaticKeepAliveClientMixin으로 State를 유지하도록 되어 있어(탭 전환
/// 시 데이터가 사라지는 문제 대응), 반대로 "탭을 다시 선택하거나 화면을
/// 새로고침하면 최신 데이터를 다시 불러와야 한다"는 요구를 만족시키려면
/// 별도 신호가 필요하다. 최상단 탭이 바뀔 때마다 이 신호를 bump하고, 각
/// Pane은 이를 구독해 다시 로드한다.
final adminRefreshSignal = StateProvider<int>((_) => 0);

void bumpAdminRefresh(WidgetRef ref) {
  ref.read(adminRefreshSignal.notifier).state++;
}

/// 알림함(다른 탭에 각각 떠 있는 알림 벨 버튼)들의 안읽은 개수 재조회를
/// 동기화하는 신호. 알림함에서 "모두 읽음" 등으로 읽음 처리를 하면 이
/// 신호를 bump해서, 다른 게시판 화면에 이미 떠 있는 벨 버튼(각자 로컬
/// State로 뱃지 카운트를 들고 있어 서로 알지 못함)도 함께 최신화한다.
final notificationRefreshSignal = StateProvider<int>((_) => 0);

void bumpNotificationRefresh(WidgetRef ref) {
  ref.read(notificationRefreshSignal.notifier).state++;
}

/// 현재(가장 최근) 활성 바텀 탭 인덱스. 셸(_MainShell) 밖(rootNavigatorKey)에
/// 쌓이는 화면(게시글 상세/작성, 알림함, DM 등)은 자체적으로 "어느 탭에서
/// 왔는지"를 모른다 — 예전엔 경로 문자열로 대충 추측했는데, 학교/인기 탭에서
/// 글쓰기·게시글 상세로 이동하면 그 추측이 틀려서 하단 네비가 지역 탭으로
/// 잘못 표시되는 문제가 있었다. 셸이 빌드될 때마다 이 값을 갱신해두고,
/// MainBottomNav가 이 값을 그대로 읽어 표시한다.
final lastActiveTabIndexProvider = StateProvider<int>((_) => 0);
