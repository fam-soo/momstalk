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

void reloadPage() => html.window.location.reload();
