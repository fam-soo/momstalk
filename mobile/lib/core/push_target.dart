/// FCM 메시지·알림함 항목의 data payload(type, post_id 등)로 이동할 라우트
/// 경로를 계산. web/firebase-messaging-sw.js의 _targetPath()와 대응되는
/// 로직(포그라운드/알림함 클릭용). router.dart와 notification_list_screen.dart
/// 양쪽에서 써서 순환 import 없이 별도 파일로 분리했다.
String? pushTargetLocation(Map<String, dynamic> data) {
  switch (data['type']) {
    case 'comment':
      final postId = data['post_id'];
      if (postId == null) return null;
      final commentId = data['comment_id'];
      // 댓글 알림은 게시글만 여는 게 아니라 해당 댓글까지 스크롤+하이라이트
      // 하도록 highlight_comment_id를 함께 넘긴다 (post_detail_screen.dart 참고).
      // "새 글" 알림도 이 'comment' 타입을 재사용하지만 comment_id가 없어
      // 게시글만 열리는 기존 동작이 그대로 유지된다.
      return commentId == null ? '/board/$postId' : '/board/$postId?highlight_comment_id=$commentId';
    case 'dm':
      final convId = data['conversation_id'];
      return convId == null ? null : '/dm/$convId';
    case 'auth_approved':
    case 'auth_rejected':
      return '/my';
    case 'academy':
      final academyId = data['academy_id'];
      return academyId == null ? null : '/academy/$academyId';
    default:
      return null;
  }
}
