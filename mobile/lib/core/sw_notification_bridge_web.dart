import 'dart:html' as html;

/// web/firebase-messaging-sw.js의 notificationclick 핸들러가 "이미 열려있는
/// 탭"을 찾으면 client.focus()와 함께 postMessage({type:'notification-click',
/// path})를 보낸다. 이 스트림은 그 메시지에서 path만 뽑아 내보낸다.
/// (탭이 없어서 서비스워커가 새로 여는 경우는 URL 자체가 목적지라 이 경로가
/// 필요 없음 — go_router가 시작 시 해시를 그대로 읽어 처리한다.)
Stream<String> notificationClickPaths() {
  return html.window.onMessage
      .where((event) {
        final data = event.data;
        return data is Map && data['type'] == 'notification-click' && data['path'] is String;
      })
      .map((event) => (event.data as Map)['path'] as String);
}
