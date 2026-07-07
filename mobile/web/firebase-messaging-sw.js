// Firebase 웹 푸시(FCM) 백그라운드 메시지 처리용 서비스워커.
// 반드시 web/ 루트에 위치해야 하며(서빙 경로: /firebase-messaging-sw.js),
// 아래 firebaseConfig는 Firebase Console > 프로젝트 설정 > 일반 > 내 앱(웹)에서
// 확인 가능한 값과 동일해야 한다. (앱 안의 firebase_web_options.dart와 동일한 값)
//
// 참고: Firebase 웹 config 값은 클라이언트에 공개되는 값으로, 프로젝트를
// 식별하는 용도일 뿐 비밀키가 아니다. Firestore/RTDB 보안 규칙 등으로 접근을
// 제어하므로 이 파일에 그대로 넣어도 안전하다.

importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyC1sQNZIQTGh9HWdsridTGjeWv_z8QqEv8',
  authDomain: 'momstalk-d65d7.firebaseapp.com',
  projectId: 'momstalk-d65d7',
  storageBucket: 'momstalk-d65d7.firebasestorage.app',
  messagingSenderId: '145724452730',
  appId: '1:145724452730:web:2452261d4c3c7e038470c3',
  measurementId: 'G-DSLGJL6KFV',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const title = notification.title || 'MomsTalk';
  const options = {
    body: notification.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data || {},
  };
  self.registration.showNotification(title, options);
});

// 알림 클릭 시 앱(또는 새 탭)으로 포커스 이동
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow('/');
    })
  );
});
