/// 사용자 클릭(제스처) 이벤트 안에서 즉시 빈 창을 열어둔 뒤, 나중에 실제 URL이
/// 준비되면 그 창을 이동시키기 위한 헬퍼.
///
/// 모바일 브라우저(특히 iOS Safari, 일부 Android 브라우저)는 `await` 이후에
/// 호출된 `window.open` / 외부 링크 열기를 "사용자 제스처 없이 발생한 팝업"으로
/// 간주해 차단하는 경우가 많다. 카카오톡 공유 URL은 API 호출로 비동기 생성해야
/// 하므로, 클릭 즉시(await 이전) 빈 창을 먼저 열어 사용자 제스처를 소비해두고
/// URL이 준비되면 그 창의 location만 옮기는 방식으로 우회한다.
/// 웹이 아닌 플랫폼에서는 아무 동작도 하지 않는다.
library web_open_helper;

export 'web_open_helper_stub.dart' if (dart.library.html) 'web_open_helper_web.dart';
