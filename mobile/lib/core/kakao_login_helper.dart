/// 카카오 로그인 SDK 예외를 사용자 친화적 한국어 문구로 변환.
/// login_screen.dart와 invite_join_screen.dart 양쪽에서 공유 —
/// 예전엔 invite_join_screen이 이 매핑 없이 raw exception.toString()을
/// 그대로 스낵바에 보여줬다.
String mapKakaoSdkError(String err) {
  if (err.contains('cancel') || err.contains('Cancel')) {
    return '카카오 로그인이 취소되었습니다.';
  }
  if (err.contains('network') || err.contains('Network') || err.contains('SocketException')) {
    return '네트워크 연결을 확인해주세요.';
  }
  return '카카오 로그인에 실패했습니다. 잠시 후 다시 시도해주세요.';
}
