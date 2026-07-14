import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Firebase 웹 푸시(VAPID) 공개 키.
/// Firebase Console > 프로젝트 설정 > Cloud Messaging > 웹 구성 > 키 쌍 생성
/// 에서 발급받아 채워 넣어야 웹 브라우저에서 알림 토큰이 발급된다.
/// `web/firebase-messaging-sw.js`의 firebaseConfig와 프로젝트가 같아야 한다.
const webVapidKey = 'BLieISX2Fz-M4KRH0UJVJqWIMJ2d9k6EOGHSYgt77_a0QUHSl1G8XMDRL6ByUQ7P-bn2kCq9lDEjPPAo_vxWMLY';

const _prefDismissedKey = 'push_banner_dismissed';
// 사용자가 "내정보 > 알림 받기"에서 명시적으로 끈 적이 있는지 기록.
// 브라우저 알림 권한은 앱이 프로그램적으로 되돌릴 수 없으므로(허용된 채로
// 남아있음), 이 로컬 플래그가 없으면 재방문 시 silentlyRegisterIfAlreadyAllowed가
// 권한만 보고 매번 토큰을 다시 등록해버려 "끄기"가 무의미해진다.
const _prefDisabledByUserKey = 'push_disabled_by_user';

/// 내정보 화면 등에서 보여줄 알림 상태.
enum PushStatus {
  on, // 권한 허용 + 사용자가 켬
  off, // 권한 허용(또는 미결정)이지만 사용자가 끔/아직 안 켬
  blocked, // 브라우저에서 권한 자체가 차단됨 — 앱에서 재요청 불가
  unavailable, // FCM 초기화 실패(설정 누락 등)
}

/// 웹 푸시(FCM) 권한 요청 / 토큰 등록 / 포그라운드 수신 처리.
///
/// 브라우저는 알림 권한을 "사용자 제스처 이후 명시적으로 요청"해야
/// 허용률이 높다 — 진입 즉시 팝업을 띄우면 대부분 거절당하고, 한 번
/// 거절되면 사용자가 브라우저 설정에서 직접 풀기 전까지는 다시 요청할
/// 방법이 없다. 그래서 배너를 먼저 보여주고, 사용자가 배너를 눌렀을 때만
/// 브라우저 권한 팝업을 띄운다.
class PushNotifications {
  static FirebaseMessaging? _tryInstance() {
    try {
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }

  static Future<NotificationSettings?> currentSettings() async {
    final messaging = _tryInstance();
    if (messaging == null) return null;
    try {
      return await messaging.getNotificationSettings();
    } catch (_) {
      return null;
    }
  }

  /// 아직 허용/거부를 결정하지 않았고, 사용자가 배너를 닫은 적도 없을 때만 노출.
  static Future<bool> shouldShowBanner() async {
    final settings = await currentSettings();
    if (settings == null) return false;
    if (settings.authorizationStatus != AuthorizationStatus.notDetermined) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_prefDismissedKey) ?? false);
  }

  static Future<void> dismissBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDismissedKey, true);
  }

  static Future<bool> _isDisabledByUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefDisabledByUserKey) ?? false;
  }

  /// 내정보 화면에서 현재 알림 상태를 판단할 때 사용.
  static Future<PushStatus> status() async {
    final settings = await currentSettings();
    if (settings == null) return PushStatus.unavailable;
    if (settings.authorizationStatus == AuthorizationStatus.denied) return PushStatus.blocked;
    final permitted = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!permitted) return PushStatus.off;
    final disabledByUser = await _isDisabledByUser();
    return disabledByUser ? PushStatus.off : PushStatus.on;
  }

  /// 배너/내정보 토글의 "켜기"에서 호출 — 브라우저 권한 팝업을 띄우고,
  /// 허용되면 토큰을 발급받아 서버에 저장한다.
  static Future<bool> requestAndRegister(WidgetRef ref) async {
    final messaging = _tryInstance();
    if (messaging == null) return false;
    try {
      final settings = await messaging.requestPermission();
      final ok = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!ok) return false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefDisabledByUserKey, false);
      return await _registerToken(ref, messaging);
    } catch (_) {
      return false;
    }
  }

  /// 내정보 토글의 "끄기"에서 호출 — 이 기기의 토큰만 서버에서 지우고
  /// 로컬에서도 폐기한다 (다른 기기에 등록된 토큰은 그대로 유지되어 계속
  /// 알림을 받는다). 브라우저 알림 권한 자체는 앱이 되돌릴 수 없어 그대로
  /// 남지만, 더 이상 이 기기로는 푸시가 오지 않는다.
  static Future<bool> disable(WidgetRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDisabledByUserKey, true);
    final messaging = _tryInstance();
    String? token;
    try {
      if (messaging != null) {
        token = kIsWeb ? await messaging.getToken(vapidKey: webVapidKey) : await messaging.getToken();
      }
    } catch (_) {}
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/auth/me/fcm-token', data: token != null ? {'token': token} : null);
    } catch (_) {
      return false;
    }
    try {
      if (messaging != null) await messaging.deleteToken();
    } catch (_) {}
    return true;
  }

  /// 이미 예전에 허용했고 사용자가 끈 적 없는 재방문 유저 — 조용히 토큰만 (재)등록.
  static Future<void> silentlyRegisterIfAlreadyAllowed(WidgetRef ref) async {
    final messaging = _tryInstance();
    if (messaging == null) return;
    try {
      if (await _isDisabledByUser()) return;
      final settings = await messaging.getNotificationSettings();
      final ok = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (ok) await _registerToken(ref, messaging);
    } catch (_) {}
  }

  static Future<bool> _registerToken(WidgetRef ref, FirebaseMessaging messaging) async {
    try {
      final token = kIsWeb
          ? await messaging.getToken(vapidKey: webVapidKey)
          : await messaging.getToken();
      if (token == null) return false;
      final dio = ref.read(dioProvider);
      await dio.post('/auth/me/fcm-token', data: {'token': token});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 포그라운드(앱을 보고 있는 중) 수신 메시지 리스너. 포그라운드에서는
  /// OS/브라우저 알림이 자동으로 뜨지 않으므로 앱 안에서 직접 보여줘야 한다.
  static void listenForegroundMessages(void Function(RemoteMessage) onMessage) {
    final messaging = _tryInstance();
    if (messaging == null) return;
    FirebaseMessaging.onMessage.listen(onMessage);
  }

  /// 앱이 백그라운드(완전 종료는 아님)에 있을 때 상단바 알림을 탭해서
  /// 앱이 포그라운드로 돌아온 경우. 이 리스너가 없으면 OS가 알림은
  /// 정상적으로 그려주지만 탭했을 때 앱 안에서 어디로도 이동시켜주지 않는다.
  static void listenBackgroundTaps(void Function(RemoteMessage) onMessageOpened) {
    final messaging = _tryInstance();
    if (messaging == null) return;
    FirebaseMessaging.onMessageOpenedApp.listen(onMessageOpened);
  }

  /// 앱이 완전히 종료된 상태에서 상단바 알림을 탭해 콜드스타트로 실행된
  /// 경우. 앱 시작 후 1회만 확인하면 된다(이후엔 listenBackgroundTaps가 처리).
  static Future<RemoteMessage?> getInitialMessage() async {
    final messaging = _tryInstance();
    if (messaging == null) return null;
    try {
      return await messaging.getInitialMessage();
    } catch (_) {
      return null;
    }
  }
}
