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
