/// FCM 메시지·알림함 항목의 data payload(type, post_id 등)로 이동할 라우트
/// 경로를 계산. web/firebase-messaging-sw.js의 _targetPath()와 대응되는
/// 로직(포그라운드/알림함 클릭용). router.dart와 notification_list_screen.dart
/// 양쪽에서 써서 순환 import 없이 별도 파일로 분리했다.
String? pushTargetLocation(Map<String, dynamic> data) {
  switch (data['type']) {
    case 'comment':
      final postId = data['post_id'];
      return postId == null ? null : '/board/$postId';
    case 'dm':
      final convId = data['conversation_id'];
      return convId == null ? null : '/dm/$convId';
    case 'auth_approved':
    case 'auth_rejected':
      return '/my';
    default:
      return null;
  }
}
