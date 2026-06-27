# MomsTalk — Claude Code 컨텍스트

## 프로젝트 개요
학부모 전용 익명 커뮤니티 앱. Flutter(Web/Android/iOS) + FastAPI + PostgreSQL × 2 + Redis.
현재 버전: v0.3 (개발 중) / 기준일: 2026-06-20

---

## 디렉터리 구조
```
C:\projects\momstalk\
├── backend/          # FastAPI 앱 (Docker 컨테이너로 실행)
│   ├── app/
│   │   ├── api/      # 라우터 (auth, posts, users, conversations, admin)
│   │   ├── core/     # profanity.py, fcm.py, sse_manager.py
│   │   ├── models/   # service_models.py, auth_models.py
│   │   └── services/ # 비즈니스 로직
│   └── alembic/      # DB 마이그레이션
├── mobile/           # Flutter 앱
│   ├── lib/
│   │   ├── core/     # api_client.dart, router.dart, theme.dart, constants.dart
│   │   └── features/ # auth/, board/, search/, dm/, profile/
│   └── web/          # index.html (Noto Sans KR 폰트 사전 로드)
└── admin/            # Streamlit 관리자 대시보드
```

---

## 기술 스택

| 영역 | 기술 |
|------|------|
| 백엔드 | FastAPI + Python 3.12, SQLAlchemy 2.x (async), Alembic |
| 인증 | JWT HS256 — Access 60분 / Refresh 30일 |
| DB | PostgreSQL × 1 (단일 통합 DB :5432), Redis :6379 |
| 모바일 | Flutter 3.x, Riverpod 2.x, go_router 14.x, Dio 5.x |
| 푸시 | Firebase Admin SDK (FCM) |
| 실시간 | SSE (asyncio Queue 기반, 단일 인스턴스) |
| 컨테이너 | Docker Compose |

---

## 로컬 개발 실행 순서

```powershell
# 1. Docker 백엔드 기동 (프로젝트 루트에서)
cd C:\projects\momstalk
docker-compose up -d db redis backend

# 2. 헬스체크
curl http://localhost:8000/health
# → {"status":"ok","app":"MomsTalk"}

# 3. DB 마이그레이션 (최초 또는 마이그레이션 추가 시)
docker exec momstalk_backend alembic upgrade head

# 4. Flutter 웹 실행
cd mobile
flutter pub get
flutter run -d chrome --web-port 3000

# 5. 관리자 대시보드 (별도 터미널)
cd admin
streamlit run app.py --server.port 8501
```

| 서비스 | 주소 |
|--------|------|
| FastAPI | http://localhost:8000 |
| Swagger UI | http://localhost:8000/docs |
| Flutter Web | http://localhost:3000 |
| Admin | http://localhost:8501 |

---

## 응답 언어 및 코드 규칙
- **항상 한국어로 응답**
- Python: 타입 힌트 필수, async/await 사용
- Flutter: Riverpod 상태관리, go_router 라우팅
- API Base URL: `http://localhost:8000/api/v1`
- 테스트: pytest (백엔드), REST Client .http 파일 (API)

---

## 인증 구조 핵심
- `anon_id` = `HMAC-SHA256(전화번호, ANON_HASH_SECRET)` — 복호화 불가
- 단일 DB: phone_verifications(SMS 코드), parent_verifications(인증 레코드), users(anon_id 참조) 모두 한 DB
- 토큰 저장: Web → SharedPreferences(localStorage) / Mobile → FlutterSecureStorage

---

## 개발 전용 API (DEBUG=true 시 사용 가능)

```http
# lurker 로그인
POST http://localhost:8000/api/v1/auth/dev/lurker-login

# 정회원 로그인 (SMS 없이)
POST http://localhost:8000/api/v1/auth/dev/login
Content-Type: application/json
{ "phone_number": "01011112222", "region": "서울", "school_code": "B100000393",
  "school_name": "테스트초등학교", "grade": 2, "school_type": "elementary" }

# lurker → 정회원 승급
POST http://localhost:8000/api/v1/auth/dev/approve-me
Authorization: Bearer {token}
```

---

## 계정 상태 판단 순서 (모든 API 공통)
1. JWT 유효성 → 실패 시 401
2. 유저 존재 여부 → 없으면 401
3. `is_banned == True` → 403 "영구 정지된 계정입니다."
4. `suspended_until > now` → 403 + `X-Suspend-Until` 헤더
5. 정상 → 유저 객체 반환

---

## 게시판 구조

| board_type | 탭명 | 접근 범위 |
|-----------|------|----------|
| `region` | 지역명 | 동일 region 유저 |
| `school` | 학교명 | 동일 school_code 유저 |
| `grade` | N학년 | 동일 학교 + 학년 |
| `free` | 전체 | 모든 인증 유저 |

lurker: school/grade 탭만 허용, region/free는 잠금 UI

---

## 신고 카테고리 (8가지)
`SPAM` / `OBSCENE` / `ABUSE` / `PERSONAL_INFO` / `MISINFORMATION` / `ILLEGAL` / `OFF_TOPIC` / `OTHER`
누적 5건 → `is_hidden = True` 자동 블라인드

---

## 스레드 익명화 레이블 (서버 런타임 계산, DB 미저장)
- 익명 댓글 + 게시글 작성자 본인 → "글쓴이"
- 익명 댓글 + 최초 등장 타인 → "익명1", "익명2" ...
- 본인 댓글 → `is_mine: true` ("나" 뱃지)

---

## 알림 발송 시점
| 이벤트 | 수신자 | 채널 |
|--------|--------|------|
| 내 게시글에 댓글 | 게시글 작성자 | FCM |
| DM 수신 (포그라운드) | 수신자 | SSE |
| DM 수신 (백그라운드) | 수신자 | FCM |

---

## 현재 완료된 주요 항목 ✅
- 카카오 앱 키 등록 및 OAuth 플로우
- go_router 라우트 순서 수정 (`/board/write` → `/board/:postId` 앞)
- 한글 폰트 Noto Sans KR 적용 (두부문자 방지)
- 토큰 저장소 플랫폼 분기 (Web/Mobile)
- 지역 표시 단위 수정 (도 → 시/군)
- S3 캡처 이미지 approve/reject 시 즉시 삭제
- Android/iOS 플랫폼 추가
- 관리자 계정 초기 시드 (`admin/seed_admin.py`)

---

## 우선순위 높은 미구현 항목 🔴
1. **관리자 시스템** — 신고 처리 API + Streamlit 대시보드
2. **Rate Limiting** — SMS/게시글 API 남용 방어 (Redis 슬라이딩 윈도우)
3. **게시글 수정 금칙어 검사** — 현재 작성 시만 적용
4. **댓글 차단 필터링** — 현재 게시글만 필터링

---

## 자주 발생하는 오류 및 해결법

| 오류 | 원인 | 해결 |
|------|------|------|
| 포트 3000 충돌 | 이전 프로세스 잔존 | `netstat -ano \| findstr :3000` → `taskkill /PID` |
| 403 Forbidden | Authorization 헤더 누락 | `/auth/dev/login`으로 토큰 재발급 |
| `FormatException: write` | go_router 라우트 순서 | 정적 경로를 파라미터 경로 앞에 배치 |
| 한글 두부문자 | Roboto 폰트 | `flutter pub get` 후 재빌드 |
| 로그인 후 무한 로딩 | LocalStorage 오염 | F12 → Application → LocalStorage 삭제 |

---

## Alembic 마이그레이션 현황
| 버전 | 내용 |
|------|------|
| 0001 | `posts.mention_tags` JSON 컬럼 |
| 0002 | `blocks`, `conversations`, `direct_messages` |
| 0003 | `suspended_until`, `warning_count`, `reports` 카테고리, `user_warnings` |
| 0004 | `users.fcm_token` |

---

## 플레이스토어 출시 전 남은 인프라 작업
- AWS Lightsail 서울 리전 ($12/월 이상, 2GB RAM)
- Swap 2GB 설정
- Let's Encrypt HTTPS
- nginx.conf 관리자 IP 화이트리스트
- GitHub Actions CI/CD
- `.env` 프로덕션 값 교체 (DEBUG=false, SECRET_KEY 64자+)