/// 서비스워커(web/firebase-messaging-sw.js)가 이미 열려있는 탭에 보내는
/// notification-click postMessage를 받아 이동 경로를 알려준다.
/// 웹이 아닌 플랫폼(모바일 앱 빌드)에서는 아무 스트림도 내보내지 않는다.
library sw_notification_bridge;

export 'sw_notification_bridge_stub.dart' if (dart.library.html) 'sw_notification_bridge_web.dart';
