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
