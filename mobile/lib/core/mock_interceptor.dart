import 'dart:async';
import 'package:dio/dio.dart';

/// mockMode = true 일 때 모든 HTTP 요청을 가로채 가짜 데이터를 반환합니다.
/// api_client.dart 의 dioProvider 에서 AppConstants.mockMode 가 true 이면 추가됩니다.
class MockInterceptor extends Interceptor {
  // 좋아요·스크랩 토글 상태 (메모리 유지)
  final _likedPosts = <int>{};
  final _scrappedPosts = <int>{};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 짧은 딜레이로 네트워크 느낌 시뮬레이션
    Future.delayed(const Duration(milliseconds: 300), () {
      try {
        final resp = _handle(options);
        handler.resolve(Response(
          requestOptions: options,
          statusCode: resp.$1,
          data: resp.$2,
        ));
      } catch (e) {
        handler.reject(DioException(requestOptions: options, message: 'Mock error: $e'));
      }
    });
  }

  (int, dynamic) _handle(RequestOptions req) {
    final method = req.method.toUpperCase();
    final path = req.path.replaceFirst(RegExp(r'^/api/v1'), '');

    // ── 인증 ──────────────────────────────────────────────────────────────
    if (path == '/auth/dev/lurker-login' && method == 'POST') {
      return (200, _fakeTokens());
    }
    if ((path == '/auth/kakao' || path == '/auth/dev/login') && method == 'POST') {
      return (200, _fakeTokens());
    }
    if (path == '/auth/refresh' && method == 'POST') {
      return (200, {'access_token': 'mock_access_token_refreshed'});
    }
    if (path == '/auth/me' && method == 'GET') {
      return (200, _myProfile);
    }
    if (path == '/auth/dev/approve-me' && method == 'POST') {
      return (200, _myProfile);
    }

    // ── 학교 검색 ──────────────────────────────────────────────────────────
    if (path.startsWith('/schools/search') && method == 'GET') {
      return (200, _schoolResults);
    }

    // ── 게시글 목록 ────────────────────────────────────────────────────────
    if (path == '/posts' && method == 'GET') {
      return (200, _postList);
    }

    // ── 게시글 작성 ────────────────────────────────────────────────────────
    if (path == '/posts' && method == 'POST') {
      return (201, _newPostResponse(req.data));
    }

    // ── 내 스크랩 목록 ─────────────────────────────────────────────────────
    if (path == '/posts/me/scraps' && method == 'GET') {
      return (200, _scraps);
    }

    // ── 게시글 상세 ─────────────────────────────────────────────────────────
    final postDetailMatch = RegExp(r'^/posts/(\d+)$').firstMatch(path);
    if (postDetailMatch != null) {
      final id = int.parse(postDetailMatch.group(1)!);
      if (method == 'GET') return (200, _postDetail(id));
      if (method == 'PATCH') return (200, _postDetail(id));
      if (method == 'DELETE') return (204, null);
    }

    // ── 좋아요 ──────────────────────────────────────────────────────────────
    final likeMatch = RegExp(r'^/posts/(\d+)/like$').firstMatch(path);
    if (likeMatch != null && method == 'POST') {
      final id = int.parse(likeMatch.group(1)!);
      final liked = _likedPosts.contains(id);
      if (liked) { _likedPosts.remove(id); } else { _likedPosts.add(id); }
      return (200, {'like_count': liked ? 4 : 5, 'is_liked': !liked});
    }

    // ── 스크랩 ─────────────────────────────────────────────────────────────
    final scrapMatch = RegExp(r'^/posts/(\d+)/scrap$').firstMatch(path);
    if (scrapMatch != null && method == 'POST') {
      final id = int.parse(scrapMatch.group(1)!);
      final scraped = _scrappedPosts.contains(id);
      if (scraped) { _scrappedPosts.remove(id); } else { _scrappedPosts.add(id); }
      return (200, {'scrap_count': scraped ? 1 : 2, 'is_scraped': !scraped});
    }

    // ── 댓글 목록 ──────────────────────────────────────────────────────────
    final commentsMatch = RegExp(r'^/posts/(\d+)/comments$').firstMatch(path);
    if (commentsMatch != null) {
      if (method == 'GET') return (200, _comments);
      if (method == 'POST') return (201, _newComment(req.data));
    }

    // ── 댓글 삭제 ─────────────────────────────────────────────────────────
    final commentDeleteMatch = RegExp(r'^/posts/(\d+)/comments/(\d+)$').firstMatch(path);
    if (commentDeleteMatch != null && method == 'DELETE') {
      return (204, null);
    }

    // ── 신고 ───────────────────────────────────────────────────────────────
    if (path == '/posts/report' && method == 'POST') {
      return (204, null);
    }

    // ── 프로필 수정 ────────────────────────────────────────────────────────
    if (path.startsWith('/users/') && method == 'PATCH') {
      return (200, _myProfile);
    }

    // ── 차단 ───────────────────────────────────────────────────────────────
    if (path.contains('/block') && method == 'POST') {
      return (200, {'blocked': true});
    }

    // ── DM ────────────────────────────────────────────────────────────────
    if (path == '/conversations' && method == 'GET') {
      return (200, _conversations);
    }
    if (path.startsWith('/conversations/') && method == 'GET') {
      return (200, _dmMessages);
    }
    if (path.startsWith('/conversations/') && method == 'POST') {
      return (201, {'id': 99, 'content': req.data?['content'] ?? '', 'sender_id': 1, 'created_at': _now()});
    }

    // ── fallback ──────────────────────────────────────────────────────────
    return (200, {});
  }

  // ── 더미 데이터 ───────────────────────────────────────────────────────────

  Map<String, dynamic> _fakeTokens() => {
    'access_token': 'mock_access_token_12345',
    'refresh_token': 'mock_refresh_token_67890',
    'member_grade': 'member',
  };

  final Map<String, dynamic> _myProfile = {
    'id': 1,
    'anon_id': 'mock_anon_001',
    'nickname': '강남맘',
    'region': '강남구',
    'school_code': 'B100000393',
    'school_name': '역삼초등학교',
    'school_type': 'elementary',
    'grade': 2,
    'class_num': 3,
    'member_grade': 'member',
    'manner_score': 36,
    'is_banned': false,
  };

  final List<Map<String, dynamic>> _postList = [
    _post(1,  '내일 역삼초 운동회 준비물 뭐예요?', '현수막이랑 돗자리 챙기면 될까요?', tags: ['역삼초등학교'], hot: true),
    _post(2,  '2학년 수학 문제집 추천해주세요', '최상위수학 vs 디딤돌 고민 중입니다', tags: ['역삼초등학교', '2학년'], pinned: true),
    _post(3,  '강남구 영어학원 정보 공유해요', '대치동 원어민 학원 다녀보신 분?', tags: ['강남구']),
    _post(4,  '점심 도시락 메뉴 추천해주세요!', '매일 싸주기 너무 힘들어요 ㅜㅜ'),
    _post(5,  '역삼초 3학년 담임 선생님 어떠세요?', '새 학기라 걱정이 많네요', tags: ['역삼초등학교']),
    _post(6,  '아이 친구 관계 고민입니다', '4학년인데 따돌림 당하는 것 같아서..', likes: 18, comments: 12),
    _post(7,  '초등 태권도 vs 수영 어떤 게 나을까요?', '체력 키우는 데는 어떤 게 효과적인지요'),
    _post(8,  '독서논술 학원 강남구 추천', '초등 저학년 괜찮은 곳 있을까요?', tags: ['강남구']),
    _post(9,  '학교 알림장 앱 다들 어떤 거 써요?', '맘스토크 써보신 분 계신가요 ㅎㅎ', likes: 31, comments: 8, hot: true),
    _post(10, '2학년 받아쓰기 잘 하는 방법', '매일 연습시키는데 점수가 안 오르네요', tags: ['2학년'], pinned: true),
  ];

  Map<String, dynamic> _postDetail(int id) {
    final base = _postList.firstWhere((p) => p['id'] == id, orElse: () => _postList.first);
    return {
      ...base,
      'content': '${base['title']}\n\n자세한 내용입니다. 많은 분들의 경험을 나눠주시면 감사하겠습니다!\n\n저는 작년에 비슷한 상황이었는데, 학교 측에 직접 문의하니 많은 도움이 됐어요. 다들 어떻게 생각하시나요?',
      'view_count': 127,
      'is_hidden': false,
      'updated_at': base['created_at'],
      'is_liked': false,
      'is_scraped': false,
      'is_mine': id == 1,
      'author': base['is_anonymous'] == true ? null : {'nickname': '강남맘', 'manner_score': 36},
    };
  }

  Map<String, dynamic> _newPostResponse(dynamic data) {
    final m = data as Map? ?? {};
    return {
      'id': 99,
      'board_type': m['board_type'] ?? 'free',
      'title': m['title'] ?? '새 게시글',
      'content': m['content'] ?? '',
      'is_anonymous': m['is_anonymous'] ?? true,
      'view_count': 0, 'like_count': 0, 'scrap_count': 0,
      'report_count': 0, 'comment_count': 0, 'is_hidden': false,
      'mention_tags': m['mention_tags'] ?? [],
      'created_at': _now(), 'updated_at': _now(),
      'is_liked': false, 'is_scraped': false, 'is_mine': true,
      'author': null,
    };
  }

  final List<Map<String, dynamic>> _comments = [
    _comment(1, '저도 운동회 때 돗자리 크게 챙겨갔어요! 그늘막도 있으면 좋더라구요 ☀️', mine: false, label: '익명1'),
    _comment(2, '작년에 갔을 때 현수막은 미리 학교에서 준비해줬어요', mine: false, label: '익명2'),
    _comment(3, '음식 넉넉히 준비하시고, 돗자리 필수예요!', mine: true,  label: '나'),
    _comment(4, '저희 반은 선생님이 공지 올려주셔서 거기 참고했어요', mine: false, label: '익명3'),
    _comment(5, '물이랑 간식 꼭 챙기세요! 생각보다 더워요', mine: false, label: '익명4'),
    _comment(6, '작은 접이식 의자도 추천해요', mine: false, label: '익명5'),
    _comment(7, '아이 이름 적힌 현수막은 반 대표가 준비하더라구요', mine: false, label: '익명6'),
    _comment(8, '작년엔 비가 와서 우산도 챙겼어요 ㅎㅎ', mine: false, label: '익명7'),
    _comment(9, '선크림 잊지 마세요! 아이들 운동장에 오래 있으니까요', mine: false, label: '익명8'),
    _comment(10,'저희는 김밥 싸갔어요. 먹기 편해서 좋았어요', mine: false, label: '글쓴이'),
  ];

  Map<String, dynamic> _newComment(dynamic data) {
    final m = data as Map? ?? {};
    return {
      'id': 200,
      'post_id': 1,
      'content': m['content'] ?? '댓글',
      'is_anonymous': m['is_anonymous'] ?? true,
      'like_count': 0,
      'is_hidden': false,
      'is_mine': true,
      'author_label': '나',
      'created_at': _now(),
    };
  }

  final List<Map<String, dynamic>> _scraps = [
    {'id': 3,  'title': '강남구 영어학원 정보 공유해요', 'board_type': 'free', 'like_count': 7, 'scrap_count': 5, 'created_at': _daysAgo(1)},
    {'id': 6,  'title': '아이 친구 관계 고민입니다',     'board_type': 'free', 'like_count': 18, 'scrap_count': 9, 'created_at': _daysAgo(2)},
    {'id': 9,  'title': '학교 알림장 앱 다들 어떤 거 써요?', 'board_type': 'free', 'like_count': 31, 'scrap_count': 14, 'created_at': _daysAgo(3)},
  ];

  final List<Map<String, dynamic>> _schoolResults = [
    {'school_code': 'B100000393', 'school_name': '역삼초등학교',  'school_type': 'elementary', 'address': '서울특별시 강남구 역삼동 123', 'region': '강남구'},
    {'school_code': 'B100000401', 'school_name': '대치초등학교',  'school_type': 'elementary', 'address': '서울특별시 강남구 대치동 456', 'region': '강남구'},
    {'school_code': 'B100000412', 'school_name': '압구정초등학교','school_type': 'elementary', 'address': '서울특별시 강남구 압구정동 789', 'region': '강남구'},
    {'school_code': 'B100000420', 'school_name': '도곡초등학교',  'school_type': 'elementary', 'address': '서울특별시 강남구 도곡동 321', 'region': '강남구'},
    {'school_code': 'B200000100', 'school_name': '해운대초등학교','school_type': 'elementary', 'address': '부산광역시 해운대구 우동 111', 'region': '해운대구'},
    {'school_code': 'B200000110', 'school_name': '센텀초등학교',  'school_type': 'elementary', 'address': '부산광역시 해운대구 센텀시티로 55', 'region': '해운대구'},
    {'school_code': 'C100000200', 'school_name': '행복중학교',    'school_type': 'middle',     'address': '경기도 수원시 팔달구 행복로 10', 'region': '수원시'},
    {'school_code': 'C100000210', 'school_name': '미래중학교',    'school_type': 'middle',     'address': '경기도 성남시 분당구 미래로 5', 'region': '성남시'},
    {'school_code': 'D100000300', 'school_name': '강남고등학교',  'school_type': 'high',       'address': '서울특별시 강남구 학동로 200', 'region': '강남구'},
    {'school_code': 'D100000310', 'school_name': '휘문고등학교',  'school_type': 'high',       'address': '서울특별시 강남구 대치동 605', 'region': '강남구'},
  ];

  final List<Map<String, dynamic>> _conversations = [
    {'id': 1, 'partner': {'id': 2, 'nickname': '서초맘'},   'last_message': '혹시 알림장 앱 써보셨어요?',         'unread_count': 1, 'updated_at': _daysAgo(0)},
    {'id': 2, 'partner': {'id': 3, 'nickname': '송파맘'},   'last_message': '운동회 같이 자리잡아요!',             'unread_count': 0, 'updated_at': _daysAgo(1)},
    {'id': 3, 'partner': {'id': 4, 'nickname': '분당맘'},   'last_message': '수학 선생님 추천 부탁드려요',         'unread_count': 2, 'updated_at': _daysAgo(1)},
    {'id': 4, 'partner': {'id': 5, 'nickname': '해운대맘'}, 'last_message': '방학 때 독서캠프 정보 있으세요?',    'unread_count': 0, 'updated_at': _daysAgo(2)},
    {'id': 5, 'partner': {'id': 6, 'nickname': '대치맘'},   'last_message': '네 감사해요 ㅎㅎ',                  'unread_count': 0, 'updated_at': _daysAgo(3)},
  ];

  final List<Map<String, dynamic>> _dmMessages = [
    {'id': 10, 'content': '안녕하세요! 역삼초 2학년이시죠?',         'sender_id': 2, 'created_at': _hoursAgo(2)},
    {'id': 11, 'content': '네 맞아요 ㅎㅎ 혹시 학원 정보 아세요?',  'sender_id': 1, 'created_at': _hoursAgo(2)},
    {'id': 12, 'content': '대치동 ○○학원 좋더라구요!',               'sender_id': 2, 'created_at': _hoursAgo(1)},
    {'id': 13, 'content': '아 정말요? 원장님 어떠세요?',              'sender_id': 1, 'created_at': _hoursAgo(1)},
    {'id': 14, 'content': '되게 꼼꼼하게 봐주세요. 강추예요',        'sender_id': 2, 'created_at': _hoursAgo(0)},
    {'id': 15, 'content': '혹시 알림장 앱 써보셨어요?',               'sender_id': 2, 'created_at': _hoursAgo(0)},
  ];
}

// ── 더미 데이터 생성 헬퍼 ─────────────────────────────────────────────────────

Map<String, dynamic> _post(
  int id,
  String title,
  String preview, {
  List<String> tags = const [],
  bool pinned = false,
  bool hot = false,
  int likes = 5,
  int comments = 3,
}) => {
  'id': id,
  'board_type': 'free',
  'title': title,
  'is_anonymous': true,
  'view_count': 40 + id * 13,
  'like_count': likes,
  'scrap_count': (likes / 3).round(),
  'comment_count': comments,
  'mention_tags': tags,
  'is_liked': false,
  'is_pinned': pinned,
  'is_hot': hot,
  'created_at': _daysAgo(id - 1),
};

Map<String, dynamic> _comment(int id, String content, {required bool mine, required String label}) => {
  'id': id,
  'post_id': 1,
  'content': content,
  'is_anonymous': true,
  'like_count': id % 3,
  'is_hidden': false,
  'is_mine': mine,
  'author_label': label,
  'author_id': mine ? 1 : null,
  'created_at': _hoursAgo(10 - id),
};

String _now() => DateTime.now().toUtc().toIso8601String();
String _daysAgo(int d) => DateTime.now().subtract(Duration(days: d)).toUtc().toIso8601String();
String _hoursAgo(int h) => DateTime.now().subtract(Duration(hours: h)).toUtc().toIso8601String();
