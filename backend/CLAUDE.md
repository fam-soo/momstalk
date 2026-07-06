# MomsTalk — Claude Code 컨텍스트

## 프로젝트 개요
학부모 전용 커뮤니티 앱(선택적 실명제). Flutter Web PWA(주력) + FastAPI + PostgreSQL 단일 DB(Supabase).
현재 버전: v0.6.1 / 기준일: 2026-07-06 / 실사용자 온보딩 진행 중 — 자세한 활성화·개선 방안은 `PRODUCT_SPEC.md` 23장 참고.

이 문서는 로컬 개발 실행법 + 자주 겪는 함정 위주 요약이다. 스키마 상세/API 목록/화면 구조/로드맵 등 전체 스펙은 `PRODUCT_SPEC.md`를 참고할 것.

---

## 디렉터리 구조
```
C:\projects\momstalk\
├── backend/          # FastAPI 앱 (Docker 컨테이너로 실행)
│   ├── app/
│   │   ├── api/v1/   # 라우터 (auth, posts, academies, admin, ...)
│   │   ├── core/     # profanity.py, fcm.py, sse_manager.py, image_sniff.py, rate_limit.py
│   │   ├── models/   # service_models.py (단일 파일, 모든 ORM 모델)
│   │   └── services/ # 비즈니스 로직 (post_service, capture_service, academy_service, ...)
│   └── alembic/versions/  # DB 마이그레이션 (0001~0023)
├── mobile/           # Flutter 앱
│   ├── lib/
│   │   ├── core/     # api_client.dart, router.dart, refresh_bus.dart, constants.dart
│   │   └── features/ # auth/, board/, academy/, profile/, dm/, admin/
│   └── web/          # index.html (Noto Sans KR 폰트 사전 로드)
└── admin/            # Streamlit 관리자 대시보드 (보조 도구 — 기본은 Flutter 인앱 /admin)
```

---

## 기술 스택

| 영역 | 기술 |
|------|------|
| 백엔드 | FastAPI + Python 3.12, SQLAlchemy 2.x (async), Alembic |
| 인증 | JWT HS256 — Access 60분 / Refresh 30일. 카카오 OAuth 액세스 토큰 → 서버 JWT 교환 |
| DB | PostgreSQL 단일 통합 DB (Supabase 호스팅), Redis (rate limit) |
| 모바일 | Flutter 3.x, Riverpod 2.x, go_router 14.x(StatefulShellRoute 5탭), Dio 5.x |
| 캡처 업로드 전용 클라이언트 | package:http `MultipartRequest` (Dio 대신 — 웹 멀티파트 안정성) |
| 이미지 저장 | Postgres BYTEA (`auth_captures.image_data`) — 별도 오브젝트 스토리지 없음 |
| 푸시 | Firebase Admin SDK (FCM) |
| 실시간 | SSE (asyncio Queue 기반, 단일 인스턴스 전제) |
| 배포 | Vercel(Flutter Web) + Render(FastAPI, `start.sh`가 자동 `alembic upgrade head`) + Supabase(PostgreSQL) |
| 컨테이너(로컬) | Docker Compose |

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
docker exec momstalk_backend alembic current   # 현재 최신: 0023

# 4. Flutter 웹 실행
cd mobile
flutter pub get
flutter run -d chrome --web-port 3000

# 5. 관리자 대시보드 (보조 — 기본은 Flutter 인앱 /admin)
cd admin
streamlit run app.py --server.port 8501
```

| 서비스 | 주소 |
|--------|------|
| FastAPI | http://localhost:8000 |
| Swagger UI | http://localhost:8000/docs |
| Flutter Web | http://localhost:3000 |
| Admin (Streamlit, 보조) | http://localhost:8501 |

> **프로덕션 배포**: `main` push → Render 자동 빌드 → `start.sh`가 alembic 헤드 동기화 후 `alembic upgrade head` → uvicorn 시작. 로컬 마이그레이션 수동 실행은 개발 중에만 필요.

---

## 응답 언어 및 코드 규칙
- **항상 한국어로 응답**
- Python: 타입 힌트 필수, async/await 사용
- Flutter: Riverpod 상태관리, go_router 라우팅
- API Base URL: `http://localhost:8000/api/v1` (프로덕션은 `constants.dart`의 `_prodUrl`)
- 테스트: pytest (백엔드), REST Client `.http` 파일 (API)
- **모델에 컬럼을 추가하면 반드시 Alembic 마이그레이션을 같이 작성한다.** `Base.metadata.create_all`은 없는 테이블만 생성하고 기존 테이블에 컬럼을 추가하지 않는다 — 이걸 놓쳐서 프로덕션에 `input_school_type`/`input_region` 컬럼이 없는 채로 몇 주간 캡처 업로드가 500으로 실패한 사고가 있었다(0023). 새 컬럼을 추가할 때마다 `alembic upgrade head`를 로컬에서 실행해 검증할 것.

---

## 인증 구조 핵심
- 카카오 로그인만 지원 (SMS/전화번호 인증 경로는 폐기됨 — `dev/login` 등 DEBUG 전용 API에만 흔적 남음)
- `anon_id`: 카카오 계정 기반 내부 식별자. `kakao_id`(카카오 숫자 ID)는 관리자 조회/검색용으로 별도 컬럼에 저장 (역추적 방지 목적으로 anon_id와 분리)
- 토큰 저장: Web → `SharedPreferences`(localStorage) / Mobile → `FlutterSecureStorage`
- 다자녀: `users.active_child_id` → `user_children` 참조. **`users.region/school_name/grade/school_type`는 레거시 필드로 "첫 자녀 등록 시"에만 동기화된다** — 프로필을 반환하는 모든 엔드포인트는 `_user_profile_with_active_child()`로 activeChild 기준 값을 덮어써서 응답하므로, 새 코드에서 `user.school_name`을 직접 읽지 말고 이 헬퍼를 통과한 응답을 사용할 것

---

## 개발 전용 API (DEBUG=true 시 사용 가능)

```http
# lurker 로그인
POST http://localhost:8000/api/v1/auth/dev/lurker-login

# 정회원 로그인 (카카오 없이)
POST http://localhost:8000/api/v1/auth/dev/login
Content-Type: application/json
{ "phone_number": "01011112222", "region": "서울", "school_code": "B100000393",
  "school_name": "테스트초등학교", "grade": 2, "school_type": "elementary" }

# lurker → 정회원 승급
POST http://localhost:8000/api/v1/auth/dev/approve-me
Authorization: Bearer {token}
```

---

## 계정 상태 판단 순서 (모든 API 공통, `get_current_user` 의존성)
1. JWT 유효성 → 실패 시 401
2. 유저 존재 여부 → 없으면 401
3. `is_banned == True` → 403 "영구 정지된 계정입니다."
4. `suspended_until > now` → 403 + `X-Suspend-Until` 헤더
5. 정상 → 유저 객체 반환

---

## 게시판 구조

| board_type | 탭명 | 접근 범위 | 익명 옵션 |
|-----------|------|----------|----------|
| `region` | 지역명 | 동일 region 유저 | 선택 가능 |
| `school` | 학교명 | 동일 school_code 유저 | 선택 가능 |
| `grade` | N학년 | 동일 학교 + 학년 | **불가 — 항상 실명(닉네임)** |
| `free` | 전체 | 모든 정회원 | 선택 가능 |
| `notice` | 공지 | 관리자 전용 작성 | **불가 — 항상 실명** |

- lurker: school/grade 탭만 읽기 허용, region/free는 잠금 UI
- 익명 허용 게시판(`ANON_ALLOWED_BOARDS` = school/free/region)이 아닌 곳에 `is_anonymous=true`를 보내도 서버가 강제로 `False`로 덮어씀
- 좋아요는 게시글 상세뿐 아니라 목록(`PostListWidget`)에서도 바로 토글 가능, `temperature_service.adjust()`로 작성자 매너온도에 반영됨

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

## 알림장 캡처 인증 (가입/자녀 추가)

이미지는 별도 오브젝트 스토리지 없이 `auth_captures.image_data`(BYTEA)에 직접 저장한다.

```
Flutter (package:http MultipartRequest, 서버가 매직바이트로 MIME 판별)
  → POST /auth/capture/upload → image_data에 즉시 저장
  → 관리자 심사(DB에서 바로 조회) → 승인/반려 시 같은 트랜잭션에서 image_data 비움
  → 승인 시 member_grade → 'member' (또는 child_add면 UserChild 생성)
```

- 과거에는 Supabase Storage 왕복(업로드 1회 + 관리자 조회 시 재다운로드 1회)이 있었고 이게 반복 업로드 오류의 원인 중 하나였음 (0022에서 제거)
- **is_trusted (관리자 부여, 인증 면제)**: 자녀 추가는 사진 업로드 화면 자체를 건너뛰고 `POST /auth/me/children`으로 즉시 등록(서버도 is_trusted/admin 아니면 403), 학교 변경(`/auth/me/profile`)은 월 1회 제한을 건너뜀
- 업로드 전 `/health`로 서버를 깨우고(Render 콜드스타트 대응), 첫 시도가 일시적 네트워크 오류면 5초 후 1회 자동 재시도 (`capture_upload_screen.dart`)

---

## 학원 후기 열람 제한 — "학원 개수" 단위 언락

과거엔 "한 학원 안에서 몇 개까지 보이는지"였으나, 지금은 **가림 처리 없이 전체 열람 가능한 학원의 개수**가 작성한 후기 수에 따라 늘어난다 (0건→1곳, 1건↑→5곳, 5건↑→무제한). `AcademyReviewUnlock` 테이블에 해금 기록을 남겨 한 번 해금한 학원은 계속 유지. 잠긴 학원은 seed 소개 + 사용자 후기 모두 한 줄 미리보기만 노출. `GET /academies/review-quota`가 게시판 상단 배너용 전역 현황을 제공.

---

## 프론트 상태 동기화 (StatefulShellRoute + 다자녀)

바텀 네비 5탭(지역/학교/학원/대화/내정보)은 `StatefulShellRoute.indexedStack`이라 tab 이동해도 State가 유지된다. 그래서 글쓰기/자녀 추가/학교 변경 후 돌아와도 목록이 자동 갱신되지 않고, 이미 선택된 탭을 다시 탭해도 새로고침되지 않는다.

`mobile/lib/core/refresh_bus.dart`의 `boardRefreshSignal`(`StateProvider<int>`)로 해결:
- 데이터를 바꾸는 지점(게시글 작성, 자녀 추가/전환, 학교 변경)에서 `bumpBoardRefresh(ref)`
- 목록/프로필 화면은 `build()`에 `ref.listen<int>(boardRefreshSignal, (prev, next) { if (prev != null && prev != next) _reload(); })` 등록
- 하단 탭에서 이미 선택된 탭을 다시 탭하면 `_MainShell`이 같은 신호를 bump
- `PostListWidget`은 `AutomaticKeepAliveClientMixin` 사용 — 없으면 오프스크린으로 밀린 탭의 State가 폐기/재생성되며 도착한 응답이 사라진 위젯에 반영되는 문제가 있었음

새 목록/상태 화면을 추가할 때는 이 패턴을 따를 것.

---

## 알림 발송 시점
| 이벤트 | 수신자 | 채널 |
|--------|--------|------|
| 내 게시글에 댓글 | 게시글 작성자 | FCM |
| DM 수신 (포그라운드) | 수신자 | SSE |
| DM 수신 (백그라운드) | 수신자 | FCM |
| 캡처 승인/반려 | 사용자 | FCM |

---

## SQL 직접 INSERT 작성 규칙

Supabase SQL Editor 등으로 테이블에 직접 행을 삽입할 때 반드시 지켜야 할 규칙.

### academy_reviews 테이블 필수 포함 컬럼

```sql
INSERT INTO academy_reviews (
  academy_id, author_id,
  subjects, teacher_styles, homework_level,
  review_text, rating,
  nickname_type, is_anonymous, is_seed,
  is_hidden, report_count,
  created_at          -- ← 반드시 포함. 누락 시 NULL → API 500
)
VALUES (
  ...,
  'anon', false, true,
  false, 0,
  NOW()
);
```

| 컬럼 | 누락 시 문제 | 올바른 기본값 |
|------|------------|------------|
| `created_at` | NULL → Pydantic `datetime` 검증 실패 → 500 | `NOW()` |
| `is_hidden` | NULL → `WHERE is_hidden = false` 조건 불일치 → 조회 누락 | `false` |
| `is_seed` | NULL → Pydantic `bool` 검증 실패 → 500 | `true` (시드) / `false` (일반) |
| `report_count` | NULL → Pydantic `int` 검증 실패 → 500 | `0` |

> **주의**: ORM `default=`는 Python 레벨 기본값이고 DB `server_default`와 다름. SQL로 직접 INSERT할 때는 ORM 기본값이 적용되지 않으므로 명시적으로 값을 지정해야 함. `nickname_type`은 `"anon"` / `"certified"`만 허용되며 그 외 값(예: `"nickname"`)은 API 요청에서 검증 오류를 낸다 — 프론트 UI 상태값과 헷갈리지 말 것 (2026-07-06 사고).

---

## 자주 발생하는 오류 및 해결법

| 오류 | 원인 | 해결 |
|------|------|------|
| 포트 3000 충돌 | 이전 프로세스 잔존 | `netstat -ano \| findstr :3000` → `taskkill /PID` |
| 403 Forbidden | Authorization 헤더 누락 | `/auth/dev/login`으로 토큰 재발급 |
| `FormatException: write` | go_router 라우트 순서 | 정적 경로(`/board/write`)를 파라미터 경로(`/board/:postId`) 앞에 배치 |
| 한글 두부문자 | Roboto 폰트 | `flutter pub get` 후 재빌드 |
| 로그인 후 무한 로딩 | LocalStorage 오염 | F12 → Application → Local Storage 삭제 |
| 캡처 업로드가 계속 "네트워크 오류" | 실제로는 서버 500(스키마 드리프트)일 수 있음 | Render 로그에서 `UndefinedColumn` 등 SQL 에러 먼저 확인. 브라우저에는 500이 그냥 커넥션 실패로 보일 수 있음 |
| 429인데 브라우저가 CORS 에러로 표시 | 커스텀 미들웨어가 CORSMiddleware보다 먼저 등록돼 최외곽을 차지 | `CORSMiddleware`는 다른 `@app.middleware("http")`보다 **나중에** `add_middleware` — Starlette는 나중에 등록된 게 최외곽 |
| 게시글 작성 시 "필수값 오류"(nickname_type) | 프론트가 UI 상태값(`'nickname'`)을 그대로 전송 | 서버는 `anon`/`certified`만 허용 — 익명 여부는 `is_anonymous`로 이미 전달되므로 `nickname_type`은 항상 `"anon"` 고정 전송 |
| 학교 게시판 진입 시 글이 안 보이다가 필터 눌러야 보임 | `TabBarView` 안 위젯이 keep-alive 없이 폐기/재생성 | `PostListWidget`에 `AutomaticKeepAliveClientMixin` 적용됨 (재발 시 다른 목록 위젯에도 동일 패턴 적용) |
| 학교 변경/자녀 추가 후 목록이 안 바뀜 | IndexedStack이라 화면 State가 유지되어 재조회 트리거가 없음 | `bumpBoardRefresh(ref)` 호출 지점 확인 (위 "프론트 상태 동기화" 절) |

---

## Alembic 마이그레이션 현황 (핵심 발췌 — 전체 목록은 `alembic/versions/` 참고)

| 버전 | 내용 |
|------|------|
| 0001~0016 | 초기 게시판/신고/DM/학원 후기/관리자 기반 테이블 |
| 0017 | `user_children`, `users.active_child_id` (다자녀 지원) |
| 0018~0020 | `academy_review_count`, 다자녀 마이그레이션, `academy_reviews.is_seed` |
| 0021 | `users.kakao_id`(indexed), `users.is_trusted` |
| 0022 | `auth_captures.image_data`(BYTEA), `image_content_type` — Supabase Storage → DB 직접 저장 |
| 0023 | `auth_captures.input_school_type`, `input_region` — **모델엔 있었지만 마이그레이션 누락으로 프로덕션에 없던 컬럼**. 캡처 업로드 500의 실제 원인이었음 |

---

## 플레이스토어/앱스토어 출시 전 남은 작업
- 현재는 Flutter Web PWA(Vercel)로 운영 중 — 네이티브 앱 스토어 출시는 MAU 안정화 후
- 카카오 비즈앱 전환 (전화번호 동의항목 사용 조건)
- Sign in with Apple (App Store 소셜 로그인 병행 의무)
- 개인정보처리방침/이용약관 URL 확정 및 스토어 등록
- 심사용 테스트 계정 준비

## 시스템 개선 우선순위 (활성화 단계 진입 — 상세는 PRODUCT_SPEC.md 23장)
1. **관측성 부재가 최우선 리스크** — 이번 세션의 여러 버그(스키마 드리프트 500, CORS 순서, nickname_type 검증)가 전부 사용자 신고로만 발견됨. Sentry 등 에러 트래킹 도입, `/health` 외부 모니터링, CI에서 모델↔마이그레이션 드리프트 자동 검출을 우선 검토
2. 온보딩 퍼널 계측 (초대 사용 → 캡처 제출 → 승인 → 첫 게시글) — 어느 단계에서 이탈하는지 지금은 알 수 없음
3. 댓글 차단 필터링 (현재 게시글만 필터링), 게시글 수정 시 금칙어 검사 미적용
4. Rate Limiting은 IP 기준 글로벌 미들웨어만 존재 — 엔드포인트별 세분화 검토
