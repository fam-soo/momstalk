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

  /// 배너의 "알림 켜기" 버튼에서 호출 — 브라우저 권한 팝업을 띄우고,
  /// 허용되면 토큰을 발급받아 서버에 저장한다.
  static Future<bool> requestAndRegister(WidgetRef ref) async {
    final messaging = _tryInstance();
    if (messaging == null) return false;
    try {
      final settings = await messaging.requestPermission();
      final ok = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!ok) return false;
      return await _registerToken(ref, messaging);
    } catch (_) {
      return false;
    }
  }

  /// 이미 예전에 허용한 재방문 유저 — 조용히 토큰만 (재)등록.
  static Future<void> silentlyRegisterIfAlreadyAllowed(WidgetRef ref) async {
    final messaging = _tryInstance();
    if (messaging == null) return;
    try {
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
}
