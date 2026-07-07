import 'package:firebase_core/firebase_core.dart';

/// Flutter Web용 Firebase 프로젝트 설정.
/// Firebase Console > 프로젝트 설정 > 일반 > 내 앱 > 웹 앱 추가에서
/// 발급받은 값으로 채워야 한다. `web/firebase-messaging-sw.js`의
/// firebaseConfig와 반드시 동일한 값이어야 한다.
///
/// (참고: 이 값들은 클라이언트에 공개되는 식별자일 뿐 비밀키가 아니다.)
const webFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyC1sQNZIQTGh9HWdsridTGjeWv_z8QqEv8',
  authDomain: 'momstalk-d65d7.firebaseapp.com',
  projectId: 'momstalk-d65d7',
  storageBucket: 'momstalk-d65d7.firebasestorage.app',
  messagingSenderId: '145724452730',
  appId: '1:145724452730:web:2452261d4c3c7e038470c3',
  measurementId: 'G-DSLGJL6KFV',
);
