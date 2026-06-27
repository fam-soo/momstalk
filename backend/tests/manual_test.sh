#!/usr/bin/env bash
# =============================================================
# MomsTalk 백엔드 수동 테스트 스크립트 (실기기 / Postman 대체)
#
# 사용법:
#   1. 서버 기동: cd backend && uvicorn app.main:app --reload
#   2. 이 스크립트 실행: bash tests/manual_test.sh
#
# 필요 도구: curl, jq
# DEBUG=true 환경이어야 /auth/dev/* 엔드포인트가 동작합니다.
# =============================================================

BASE="http://localhost:8000/api/v1"
PASS="\033[32m[PASS]\033[0m"
FAIL="\033[31m[FAIL]\033[0m"

check() {
  local label="$1"
  local code="$2"
  local expected="$3"
  if [ "$code" -eq "$expected" ]; then
    echo -e "$PASS $label ($code)"
  else
    echo -e "$FAIL $label (expected $expected, got $code)"
  fi
}

echo ""
echo "=== 1. 서버 헬스체크 ==="
CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health)
check "GET /health" "$CODE" 200

echo ""
echo "=== 2. 개발 전용 로그인 ==="
LURKER=$(curl -s -X POST "$BASE/auth/dev/lurker-login")
LURKER_TOKEN=$(echo "$LURKER" | jq -r '.access_token')
check "POST /auth/dev/lurker-login" "$([ -n "$LURKER_TOKEN" ] && echo 200 || echo 0)" 200

MEMBER_RESP=$(curl -s -X POST "$BASE/auth/dev/login" \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number":"01011112222",
    "region":"서울",
    "school_code":"B100000393",
    "school_name":"테스트초등학교",
    "grade":2,
    "school_type":"elementary"
  }')
MEMBER_TOKEN=$(echo "$MEMBER_RESP" | jq -r '.access_token')
check "POST /auth/dev/login" "$([ -n "$MEMBER_TOKEN" ] && echo 200 || echo 0)" 200

# 정회원 승급
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/auth/dev/approve-me" \
  -H "Authorization: Bearer $MEMBER_TOKEN")
check "POST /auth/dev/approve-me" "$CODE" 204

echo ""
echo "=== 3. 내 프로필 조회 ==="
ME=$(curl -s "$BASE/auth/me" -H "Authorization: Bearer $MEMBER_TOKEN")
echo "  nickname: $(echo $ME | jq -r '.nickname')"
echo "  grade: $(echo $ME | jq -r '.member_grade')"
check "GET /auth/me (member)" "$(echo $ME | jq -r '.member_grade == \"member\"' | grep -c true)" 1

echo ""
echo "=== 4. 닉네임 변경 ==="
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "$BASE/auth/me/nickname" \
  -H "Authorization: Bearer $MEMBER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"nickname":"테스트맘"}')
check "PATCH /auth/me/nickname" "$CODE" 200

echo ""
echo "=== 5. 게시글 CRUD ==="
POST_RESP=$(curl -s -X POST "$BASE/posts" \
  -H "Authorization: Bearer $MEMBER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"테스트 게시글","content":"내용입니다.","board_type":"free"}')
POST_ID=$(echo "$POST_RESP" | jq -r '.id')
check "POST /posts (create)" "$([ -n "$POST_ID" ] && echo 201 || echo 0)" 201
echo "  created post_id: $POST_ID"

CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/posts?board_type=free" \
  -H "Authorization: Bearer $MEMBER_TOKEN")
check "GET /posts?board_type=free" "$CODE" 200

CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/posts/$POST_ID" \
  -H "Authorization: Bearer $MEMBER_TOKEN")
check "GET /posts/$POST_ID" "$CODE" 200

CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "$BASE/posts/$POST_ID" \
  -H "Authorization: Bearer $MEMBER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"수정된 제목","content":"수정된 내용"}')
check "PATCH /posts/$POST_ID" "$CODE" 200

echo ""
echo "=== 6. 좋아요 · 스크랩 ==="
LIKE=$(curl -s -X POST "$BASE/posts/$POST_ID/like" \
  -H "Authorization: Bearer $MEMBER_TOKEN")
check "POST /posts/$POST_ID/like (toggle on)" "$(echo $LIKE | jq -r '.liked')" true

SCRAP=$(curl -s -X POST "$BASE/posts/$POST_ID/scrap" \
  -H "Authorization: Bearer $MEMBER_TOKEN")
check "POST /posts/$POST_ID/scrap (toggle on)" "$(echo $SCRAP | jq -r '.scrapped')" true

CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/posts/me/scraps" \
  -H "Authorization: Bearer $MEMBER_TOKEN")
check "GET /posts/me/scraps" "$CODE" 200

echo ""
echo "=== 7. 댓글 ==="
COMMENT_RESP=$(curl -s -X POST "$BASE/posts/$POST_ID/comments" \
  -H "Authorization: Bearer $MEMBER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content":"테스트 댓글입니다"}')
COMMENT_ID=$(echo "$COMMENT_RESP" | jq -r '.id')
check "POST /posts/$POST_ID/comments" "$([ -n "$COMMENT_ID" ] && echo 201 || echo 0)" 201

CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/posts/$POST_ID/comments" \
  -H "Authorization: Bearer $MEMBER_TOKEN")
check "GET /posts/$POST_ID/comments" "$CODE" 200

CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$BASE/posts/$POST_ID/comments/$COMMENT_ID/like" \
  -H "Authorization: Bearer $MEMBER_TOKEN")
check "POST /posts/$POST_ID/comments/$COMMENT_ID/like" "$CODE" 200

CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X DELETE "$BASE/posts/$POST_ID/comments/$COMMENT_ID" \
  -H "Authorization: Bearer $MEMBER_TOKEN")
check "DELETE comment" "$CODE" 204

echo ""
echo "=== 8. 신고 ==="
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/posts/report" \
  -H "Authorization: Bearer $MEMBER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"target_type\":\"post\",\"target_id\":$POST_ID,\"category\":\"SPAM\",\"reason\":\"테스트 신고\"}")
check "POST /posts/report" "$CODE" 204

echo ""
echo "=== 9. DM ==="
# 두 번째 유저 생성
TOKEN2=$(curl -s -X POST "$BASE/auth/dev/login" \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number":"01077776666",
    "region":"부산",
    "school_code":"D987654321",
    "school_name":"두번째초등학교",
    "grade":3,
    "school_type":"elementary"
  }' | jq -r '.access_token')
curl -s -o /dev/null -X POST "$BASE/auth/dev/approve-me" -H "Authorization: Bearer $TOKEN2"
USER2_ID=$(curl -s "$BASE/auth/me" -H "Authorization: Bearer $TOKEN2" | jq -r '.id')

CONV=$(curl -s -X POST "$BASE/conversations/$USER2_ID" \
  -H "Authorization: Bearer $MEMBER_TOKEN")
CONV_ID=$(echo "$CONV" | jq -r '.id')
check "POST /conversations/$USER2_ID" "$([ -n "$CONV_ID" ] && echo 200 || echo 0)" 200

MSG=$(curl -s -X POST "$BASE/conversations/$CONV_ID/messages" \
  -H "Authorization: Bearer $MEMBER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content":"안녕하세요!"}')
check "POST /conversations/$CONV_ID/messages" "$(echo $MSG | jq -r '.content')" "안녕하세요!"

CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "$BASE/conversations/$CONV_ID/messages" \
  -H "Authorization: Bearer $MEMBER_TOKEN")
check "GET /conversations/$CONV_ID/messages" "$CODE" 200

echo ""
echo "=== 10. 초대 링크 ==="
INVITE=$(curl -s -X POST "$BASE/auth/invite/generate" \
  -H "Authorization: Bearer $MEMBER_TOKEN")
INVITE_TOKEN=$(echo "$INVITE" | jq -r '.token')
check "POST /auth/invite/generate" "$([ -n "$INVITE_TOKEN" ] && echo 200 || echo 0)" 200
echo "  invite deeplink: $(echo $INVITE | jq -r '.deeplink')"

echo ""
echo "=== 11. 게시글 삭제 ==="
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE/posts/$POST_ID" \
  -H "Authorization: Bearer $MEMBER_TOKEN")
check "DELETE /posts/$POST_ID" "$CODE" 204

echo ""
echo "============================="
echo " 수동 테스트 완료"
echo "============================="
