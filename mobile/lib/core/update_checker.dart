/// 배포마다 바뀌는 build-id로 "지금 보고 있는 화면이 최신 빌드인지"를
/// 확인하는 헬퍼. Flutter Web PWA는 브라우저/서비스워커 캐싱 때문에 새
/// 기능을 배포해도 사용자가 새로고침하지 않으면 예전 화면이 계속 보이는
/// 문제가 있다 — 실제로 관리자 화면 버튼이 안 보인다는 리포트의 원인이었다.
/// 웹이 아닌 플랫폼(모바일 앱 빌드)에서는 아무 동작도 하지 않는다.
library update_checker;

export 'update_checker_stub.dart' if (dart.library.html) 'update_checker_web.dart';
