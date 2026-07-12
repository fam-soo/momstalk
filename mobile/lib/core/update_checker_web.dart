import 'dart:html' as html;

/// 현재 로드된 index.html에 CI가 배포 시점마다 새로 심어주는 build-id
/// 메타 태그. 이 값은 페이지를 새로고침하기 전까지 절대 바뀌지 않는다.
String? currentBuildId() {
  final meta = html.document.querySelector('meta[name="build-id"]');
  return meta?.getAttribute('content');
}

/// 서버(정적 호스팅)에 있는 최신 빌드의 build-id를 캐시 없이 조회.
/// index.html 자체가 아니라 별도의 초경량 텍스트 파일을 쓰는 이유: 브라우저/
/// CDN이 index.html은 이미 캐시했더라도 이 파일은 항상 새로 받아오게 하기 위함.
Future<String?> fetchLatestBuildId() async {
  try {
    final req = await html.HttpRequest.request(
      '/build-id.txt?_=${DateTime.now().millisecondsSinceEpoch}',
      method: 'GET',
      requestHeaders: {'Cache-Control': 'no-cache'},
    );
    final body = req.responseText?.trim();
    return (body != null && body.isNotEmpty) ? body : null;
  } catch (_) {
    return null;
  }
}

/// 그냥 location.reload()만 호출하면 Flutter Web의 서비스워커
/// (flutter_service_worker.js)가 예전에 캐시해둔 main.dart.js 등을 그대로
/// 서빙해서 실제로는 새 빌드가 반영되지 않는 문제가 있었다 — "새로고침
/// 버튼을 눌러도 안 바뀌고 브라우저를 완전히 껐다 켜야만 반영된다"는 리포트의
/// 원인. 브라우저 탭을 코드로 강제 종료-재실행할 수는 없으므로(브라우저
/// 보안 정책상 불가), 대신 서비스워커 등록 해제 + 캐시 전체 삭제 후 새로고침해
/// 껐다 켜는 것과 동일한 효과(모든 파일을 서버에서 새로 받아옴)를 낸다.
Future<void> reloadPage() async {
  try {
    if (html.window.navigator.serviceWorker != null) {
      final registrations = await html.window.navigator.serviceWorker!.getRegistrations();
      for (final reg in registrations) {
        await reg.unregister();
      }
    }
    final cacheStorage = html.window.caches;
    if (cacheStorage != null) {
      final keys = await cacheStorage.keys();
      for (final key in keys) {
        await cacheStorage.delete(key);
      }
    }
  } catch (_) {
    // 서비스워커/캐시 정리가 실패해도 새로고침 자체는 시도한다.
  }
  html.window.location.reload();
}
