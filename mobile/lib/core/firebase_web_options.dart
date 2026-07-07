import 'package:firebase_core/firebase_core.dart';

/// Flutter Web용 Firebase 프로젝트 설정.
/// Firebase Console > 프로젝트 설정 > 일반 > 내 앱 > 웹 앱 추가에서
/// 발급받은 값으로 채워야 한다. `web/firebase-messaging-sw.js`의
/// firebaseConfig와 반드시 동일한 값이어야 한다.
///
/// (참고: 이 값들은 클라이언트에 공개되는 식별자일 뿐 비밀키가 아니다.)
const webFirebaseOptions = FirebaseOptions(
  apiKey: 'TODO_FIREBASE_WEB_API_KEY',
  authDomain: 'TODO_FIREBASE_PROJECT_ID.firebaseapp.com',
  projectId: 'TODO_FIREBASE_PROJECT_ID',
  storageBucket: 'TODO_FIREBASE_PROJECT_ID.appspot.com',
  messagingSenderId: 'TODO_FIREBASE_MESSAGING_SENDER_ID',
  appId: 'TODO_FIREBASE_WEB_APP_ID',
);
