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

// 알림 데이터(type, post_id 등)로 실제 목적지 경로를 계산한다.
// Flutter Web은 URL 전략을 별도로 설정하지 않아 기본값인 해시(#) 라우팅을
// 쓰므로 반드시 '/#/...' 형태여야 go_router가 올바른 화면으로 진입한다.
function _targetPath(data) {
  data = data || {};
  switch (data.type) {
    case 'comment':
      return data.post_id ? `/#/board/${data.post_id}` : '/#/region';
    case 'dm':
      return data.conversation_id ? `/#/dm/${data.conversation_id}` : '/#/dm';
    case 'auth_approved':
    case 'auth_rejected':
      return '/#/my';
    default:
      return '/#/region';
  }
}

// 알림 클릭 시 해당 게시글/대화로 이동한다. 이미 열려있는 탭이 있으면 그
// 탭을 포커스하면서 경로를 이동시키고(postMessage), 없으면 그 경로로 새 탭을 연다.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetPath = _targetPath(event.notification.data);
  const targetUrl = self.location.origin + targetPath;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          client.postMessage({ type: 'notification-click', path: targetPath });
          return client.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow(targetUrl);
    })
  );
});
