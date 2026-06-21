# MomsTalk — 제품 사양서 및 개발 현황 문서

> 작성 기준일: 2026-06-20  
> 현재 버전: v0.3 (개발 중)  
> 플랫폼: Flutter Web (개발) / Android·iOS (예정)  
> 백엔드: FastAPI + PostgreSQL × 2 + Redis

---

## 목차

1. [서비스 개요](#1-서비스-개요)
2. [아키텍처 설계](#2-아키텍처-설계)
3. [인증 및 계정 설계](#3-인증-및-계정-설계)
4. [DB 스키마 상세](#4-db-스키마-상세)
5. [API 엔드포인트 목록](#5-api-엔드포인트-목록)
6. [화면 구성 및 UI 레이아웃](#6-화면-구성-및-ui-레이아웃)
7. [게시판 구조](#7-게시판-구조)
8. [신고 시스템](#8-신고-시스템)
9. [차단 및 숨기기](#9-차단-및-숨기기)
10. [1:1 대화 (DM)](#10-11-대화-dm)
11. [계정 정지 시스템](#11-계정-정지-시스템)
12. [스레드 익명화](#12-스레드-익명화)
13. [금칙어 필터링](#13-금칙어-필터링)
14. [푸시 알림 (FCM)](#14-푸시-알림-fcm)
15. [실시간 DM (SSE)](#15-실시간-dm-sse)
16. [보안 설계](#16-보안-설계)
17. [관리자 시스템 (설계안)](#17-관리자-시스템-설계안)
18. [미구현 / 보완 필요 항목](#18-미구현--보완-필요-항목)
19. [인프라 및 배포](#19-인프라-및-배포)

---

## 1. 서비스 개요

**MomsTalk**는 학부모 전용 익명 커뮤니티 앱이다. 핵심 원칙:

- **완전 익명**: 닉네임은 자동 생성, 게시글·댓글 익명 선택 가능
- **지역/학교 인증**: NEIS(교육부 나이스 API) 기반 실제 학교 확인
- **이중 DB 분리**: 전화번호(신원) DB ↔ 활동 DB를 물리적으로 분리하여 역추적 원천 차단
- **자동 중재**: 신고 5건 누적 시 자동 블라인드, 카테고리별 신고 처리
- **스레드 익명화**: 같은 게시글 내 댓글 작성자를 "글쓴이/익명1/익명2..." 방식으로 구분
- **서버 금칙어 필터**: 게시글·댓글 저장 전 서버에서 금칙어 검사
- **실시간 알림**: FCM 푸시 + SSE(Server-Sent Events) DM 실시간 수신

---

## 2. 아키텍처 설계

```
┌──────────────────────────────────────────────────────────┐
│  Flutter App (Web / Android / iOS)                       │
│  ┌──────────────┐ ┌──────────┐ ┌─────────────────────┐  │
│  │ 게시판 탭    │ │ 검색 탭  │ │ 대화(DM) 탭         │  │
│  └──────────────┘ └──────────┘ └─────────────────────┘  │
│  Dio + JWT Bearer + flutter_secure_storage               │
│  SSE: http 패키지 (EventSource 방식)                     │
└─────────────────────┬────────────────────────────────────┘
                      │ HTTPS / REST / SSE
┌─────────────────────▼────────────────────────────────────┐
│  FastAPI (Python 3.12, Uvicorn)                          │
│  Port 8000 — Docker Container: momstalk_backend          │
│                                                          │
│  /api/v1/auth/*         인증 + FCM 토큰 등록             │
│  /api/v1/schools/*      NEIS 학교 검색                   │
│  /api/v1/posts/*        게시글/댓글/신고                 │
│  /api/v1/users/*        차단 (Block)                     │
│  /api/v1/conversations/* 1:1 DM                         │
│  /api/v1/stream         SSE 실시간 이벤트 스트림         │
│                                                          │
│  core/profanity.py      금칙어 서버 필터                 │
│  core/fcm.py            Firebase Admin SDK 발송          │
│  core/sse_manager.py    인메모리 asyncio Queue 매니저    │
└──────┬───────────────────────────────┬───────────────────┘
       │                               │
┌──────▼──────┐               ┌────────▼───────┐
│ Auth DB     │               │ Service DB     │
│ PostgreSQL  │               │ PostgreSQL     │
│ :5433       │               │ :5432          │
│ 전화번호    │               │ 활동 데이터    │
│ SMS 인증코드│  anon_id      │ (신원 정보 無) │
│ 학부모 인증 │ ──────────▶   │ 게시글/댓글   │
│             │  (단방향)     │ 좋아요/스크랩  │
└─────────────┘               │ DM/차단/신고   │
                              │ 경고 이력      │
                              └────────────────┘
                                     │
                              ┌──────▼─────┐
                              │   Redis    │
                              │  :6379     │
                              │ (예정:     │
                              │ Rate Limit │
                              │ 토큰 블랙  │
                              │ 리스트)    │
                              └────────────┘
```

### 기술 스택

| 영역 | 기술 |
|------|------|
| 백엔드 프레임워크 | FastAPI 0.x + Python 3.12 |
| ORM | SQLAlchemy 2.x (async) |
| DB 마이그레이션 | Alembic |
| 인증 | JWT (HS256) — Access 60분 / Refresh 30일 |
| 푸시 알림 | Firebase Admin SDK (firebase-admin) |
| 실시간 통신 | SSE (Server-Sent Events) — asyncio Queue 기반 |
| 모바일 프레임워크 | Flutter 3.x |
| 상태 관리 | Riverpod 2.x |
| 라우팅 | go_router 14.x (StatefulShellRoute) |
| HTTP 클라이언트 | Dio 5.x (자동 토큰 갱신 인터셉터) + http 1.x (SSE 스트림) |
| 컨테이너 | Docker Compose |

---

## 3. 인증 및 계정 설계

### 3-1. 인증 플로우

```
사용자 전화번호 입력
        ↓
SMS 인증 코드 발송 (6자리, 5분 TTL)
        ↓
코드 입력 확인
        ↓
학교 선택 (NEIS API 검색)
        ↓
지역/학년 입력
        ↓
서버: HMAC-SHA256(전화번호, ANON_HASH_SECRET) = anon_id 생성
        ↓
├── Auth DB: ParentVerification upsert (anon_id + 학교정보)
└── Service DB: User upsert (anon_id만 참조, 전화번호 無)
        ↓
JWT Access Token + Refresh Token 발급 → 앱 저장
        ↓
앱 시작 시: POST /auth/me/fcm-token (FCM 디바이스 토큰 서버 등록)
```

### 3-2. 익명화 구조

| 항목 | 설명 |
|------|------|
| `anon_id` | `HMAC-SHA256(전화번호, ANON_HASH_SECRET)` — 복호화 불가 |
| 1인 1계정 | 동일 전화번호 → 항상 동일 `anon_id` → 중복 가입 방지 |
| Auth DB | 전화번호 + anon_id 보관. 서비스 DB와 물리적 별도 PostgreSQL |
| Service DB | anon_id만 참조. 전화번호 역추적 수학적 불가 |
| 서비스 내부 | 게시글/댓글에는 `author_id`(정수)만 저장. 익명 선택 시 닉네임 미노출 |

### 3-3. 계정 필드 (Service DB — `users` 테이블)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | 서비스 내부 식별자 |
| `anon_id` | String(64) UNIQUE | HMAC 해시값 |
| `nickname` | String(30) | 자동 생성 (예: "따뜻한엄마3829") |
| `region` | String(30) | 지역 (예: 기장군) |
| `school_code` | String(20) | NEIS 학교 코드 |
| `school_name` | String(100) | 학교명 |
| `grade` | Integer | 학년 |
| `class_num` | Integer | 반 |
| `school_type` | String(10) | elementary / middle / high |
| `manner_score` | Integer | 매너온도 (초기값 36) |
| `fcm_token` | String(256) | Firebase 푸시 토큰 (기기 변경 시 갱신) |
| `is_banned` | Boolean | 영구 정지 여부 |
| `suspended_until` | DateTime | 기간 정지 해제 시각 (NULL이면 정지 없음) |
| `warning_count` | Integer | 누적 경고 횟수 |
| `profile_updated_at` | DateTime | 프로필 최종 수정일 (월 1회 제한용) |

### 3-4. 닉네임 자동 생성 규칙

```
형용사(8개) + 명사(5개) + 4자리 숫자
예: "지혜로운학부모4712", "용감한아빠0031"
```

---

## 4. DB 스키마 상세

### Service DB 테이블 목록

#### `users` — 유저

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | |
| `anon_id` | String(64) UNIQUE | HMAC 해시, 신원 역추적 불가 |
| `nickname` | String(30) | 자동 생성 |
| `region` | String(30) | 지역 |
| `school_code` | String(20) | NEIS 학교 코드 |
| `school_name` | String(100) | |
| `grade` | Integer | 학년 |
| `class_num` | Integer | 반 (nullable) |
| `school_type` | String(10) | elementary / middle / high |
| `manner_score` | Integer | 기본값 36 |
| `fcm_token` | String(256) | Firebase 푸시 토큰 (nullable) |
| `is_banned` | Boolean | 영구 정지 |
| `suspended_until` | DateTime | 기간 정지 해제 시각 (nullable) |
| `warning_count` | Integer | 누적 경고 수 (기본값 0) |
| `profile_updated_at` | DateTime | 프로필 최종 수정일 |
| `created_at` | DateTime | |

#### `posts` — 게시글

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | |
| `author_id` | FK → users | |
| `board_type` | String(20) | region / school / grade / free |
| `school_code` | String(20) | 게시글 작성 시 소속 학교 |
| `grade` | Integer | grade 게시판에서만 사용 |
| `title` | String(200) | 2~200자 |
| `content` | Text | 5자 이상 |
| `is_anonymous` | Boolean | 익명 여부 |
| `mention_tags` | JSON | @태그 배열 (free 게시판) |
| `view_count` | Integer | |
| `like_count` | Integer | |
| `scrap_count` | Integer | |
| `report_count` | Integer | |
| `is_hidden` | Boolean | 신고 누적 자동 블라인드 |
| `is_deleted` | Boolean | 소프트 삭제 |
| `created_at` | DateTime | |
| `updated_at` | DateTime | |

#### `comments` — 댓글

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | |
| `post_id` | FK → posts | |
| `author_id` | FK → users | |
| `parent_id` | FK → comments | NULL이면 루트 댓글, 있으면 대댓글 |
| `content` | Text | |
| `is_anonymous` | Boolean | |
| `like_count` | Integer | |
| `report_count` | Integer | |
| `is_hidden` | Boolean | |
| `is_deleted` | Boolean | |
| `created_at` | DateTime | |

#### `likes` — 좋아요

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `user_id` | FK → users | |
| `target_type` | String(10) | post / comment |
| `target_id` | Integer | |
| UNIQUE | (user_id, target_type, target_id) | 중복 방지 |

#### `scraps` — 스크랩

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `user_id` | FK → users | |
| `post_id` | FK → posts | |
| UNIQUE | (user_id, post_id) | |

#### `reports` — 신고

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `reporter_id` | FK → users | |
| `target_type` | String(10) | post / comment |
| `target_id` | Integer | |
| `category` | String(20) | 신고 카테고리 코드 (8가지) |
| `reason` | String(200) | 기타 사유 직접 입력 (category=OTHER일 때) |
| `status` | String(20) | pending / reviewed / dismissed / actioned |
| `reviewed_by` | Integer | 관리자 user_id (nullable) |
| `reviewed_at` | DateTime | 검토 시각 (nullable) |
| `action_taken` | String(50) | warned / suspended_7d / suspended_30d / banned / cleared |
| `created_at` | DateTime | |
| UNIQUE | (reporter_id, target_type, target_id) | 중복 신고 방지 |

#### `user_warnings` — 경고/정지 이력

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | |
| `user_id` | FK → users | 조치 대상 |
| `reason` | Text | 위반 사유 |
| `warning_type` | String(20) | warning / suspend_7d / suspend_30d / banned |
| `issued_by` | Integer | 관리자 user_id (NULL이면 자동 처리) |
| `expires_at` | DateTime | 정지 해제 시각 (NULL이면 영구) |
| `created_at` | DateTime | |

#### `blocks` — 차단

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `user_id` | FK → users | 차단한 사람 |
| `blocked_user_id` | Integer | 차단당한 사람 |
| UNIQUE | (user_id, blocked_user_id) | |

#### `conversations` — 1:1 대화방

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `user_a_id` | FK → users | 항상 더 작은 ID |
| `user_b_id` | FK → users | 항상 더 큰 ID |
| `last_message_at` | DateTime | 목록 정렬용 |
| UNIQUE | (user_a_id, user_b_id) | 동일 대화방 중복 방지 |

#### `direct_messages` — DM 메시지

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `conversation_id` | FK → conversations | |
| `sender_id` | FK → users | |
| `content` | Text | |
| `is_read` | Boolean | 읽음 여부 |
| `created_at` | DateTime | |

### Auth DB 테이블 목록

#### `phone_verifications` — SMS 인증코드

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `phone_number` | String(20) | |
| `code` | String(6) | 6자리 랜덤 |
| `is_used` | Boolean | 사용 여부 |
| `expires_at` | DateTime | 발송 후 5분 |

#### `parent_verifications` — 학부모 인증 레코드

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `anon_id` | String(64) UNIQUE | HMAC 해시값 |
| `school_code` | String(20) | |
| `school_name` | String(100) | |
| `grade` | Integer | |
| `school_type` | String(10) | |
| `is_active` | Boolean | 계정 활성 여부 |

### Alembic 마이그레이션 이력

| 버전 | 설명 |
|------|------|
| 0001 | `posts.mention_tags` JSON 컬럼 추가 |
| 0002 | `blocks`, `conversations`, `direct_messages` 테이블 추가 |
| 0003 | `users.suspended_until`, `users.warning_count`, `reports` 카테고리 컬럼 추가, `user_warnings` 테이블 추가 |
| 0004 | `users.fcm_token` 컬럼 추가 |

---

## 5. API 엔드포인트 목록

Base URL: `http://{host}/api/v1`  
인증 방식: `Authorization: Bearer {access_token}` (모든 유저 전용 API 필수)

### 인증 (auth)

| Method | Path | 설명 |
|--------|------|------|
| POST | `/auth/sms/send` | SMS 인증 코드 발송 |
| POST | `/auth/sms/verify` | SMS 코드 검증 → sms_token 반환 |
| POST | `/auth/parent/verify` | 학교 정보 + sms_token → JWT 발급 |
| POST | `/auth/refresh` | Refresh Token → 새 Access Token |
| GET | `/auth/me` | 내 프로필 조회 |
| PATCH | `/auth/me/nickname` | 닉네임 수정 |
| PATCH | `/auth/me/profile` | 프로필 수정 (지역/학교/학년, 월 1회 제한) |
| POST | `/auth/me/fcm-token` | FCM 디바이스 토큰 등록/갱신 |

### 학교 검색 (schools)

| Method | Path | 설명 |
|--------|------|------|
| GET | `/schools/search?q={query}&region={시도명}` | NEIS API 학교 검색 |

### 게시글 (posts)

| Method | Path | 설명 |
|--------|------|------|
| GET | `/posts?board_type={}&page={}&size={}&q={}` | 게시글 목록 (검색 포함) |
| POST | `/posts` | 게시글 작성 (금칙어 검사 포함) |
| GET | `/posts/{id}` | 게시글 상세 (조회수 +1) |
| PATCH | `/posts/{id}` | 게시글 수정 (본인만) |
| DELETE | `/posts/{id}` | 게시글 소프트 삭제 (본인만) |
| POST | `/posts/{id}/like` | 좋아요 토글 |
| POST | `/posts/{id}/scrap` | 스크랩 토글 |
| GET | `/posts/me/scraps` | 내 스크랩 목록 |
| GET | `/posts/{id}/comments` | 댓글 목록 (스레드 익명화 레이블 포함) |
| POST | `/posts/{id}/comments` | 댓글 작성 (금칙어 검사 + 게시글 작성자 FCM 발송) |
| DELETE | `/posts/{id}/comments/{cid}` | 댓글 소프트 삭제 (본인만) |
| POST | `/posts/{id}/comments/{cid}/like` | 댓글 좋아요 토글 |
| POST | `/posts/report` | 신고 (카테고리 선택 + 사유 입력) |

### 차단 (users)

| Method | Path | 설명 |
|--------|------|------|
| POST | `/users/{target_id}/block` | 차단 등록 |
| DELETE | `/users/{target_id}/block` | 차단 해제 |

### DM / 실시간 (conversations, stream)

| Method | Path | 설명 |
|--------|------|------|
| GET | `/conversations` | 내 대화 목록 (안 읽은 메시지 수 포함) |
| POST | `/conversations/{other_user_id}` | 대화방 생성 또는 기존 반환 |
| GET | `/conversations/{id}/messages` | 메시지 목록 (읽음 처리 자동) |
| POST | `/conversations/{id}/messages` | 메시지 전송 (SSE 이벤트 + FCM 발송) |
| GET | `/stream` | SSE 실시간 이벤트 스트림 (DM 수신 등) |

---

## 6. 화면 구성 및 UI 레이아웃

### 6-1. 전체 네비게이션 구조

```
앱 진입
  ├── [미인증] → 전화번호 입력 → SMS 인증 → 학교 선택 → 게시판
  └── [인증됨] → 게시판 (바텀 네비)

바텀 네비게이션 (3탭, StatefulShellRoute)
  ├── [게시판] — 지역/학교/학년/전체 TabBar
  ├── [검색]   — 전체 게시판 텍스트 검색
  └── [대화]   — 1:1 DM 목록 (SSE 실시간 연결)

전체 화면 (바텀 네비 위)
  ├── 게시글 상세 (/board/:postId)
  ├── 글쓰기 (/board/write)
  ├── DM 채팅 (/dm/:convId)
  └── 프로필 (/profile)
```

### 6-2. 게시판 화면 (board_screen)

```
AppBar: "MomsTalk"                          [프로필 아이콘]
─────────────────────────────────────────────────────────
TabBar: [기장군] [부산중앙고등학교] [1학년] [전체]
─────────────────────────────────────────────────────────
게시글 카드 (Blind 스타일):
┌───────────────────────────────────────────────────┐
│ 🔵 익명  ·  2시간전                         [···] │
│                                                   │
│ [추천] 게시글 제목이 여기 들어갑니다               │
│ @기장군  @1학년  (mention 태그)                   │
│                                                   │
│ ♡ 12    💬 5    👁 128                           │
└───────────────────────────────────────────────────┘

[글쓰기 FAB]
```

**[···] 더보기 액션 시트:**
- 게시물/회원 신고하기 → 카테고리 선택 다이얼로그
- 이 회원의 글 모두 숨기기

### 6-3. 게시글 상세 화면 (post_detail_screen)

```
AppBar: "게시글"                            [더보기 ···]
─────────────────────────────────────────────────────────
제목 (bold, large)
작성자 닉네임 또는 익명          조회 N
──────────────────────────────────────────
본문 내용 (line-height 1.6)

[♡ 공감 N]  [🔖 스크랩 N]
──────────────────────────────────────────
댓글 N
  🔵 글쓴이  [작성자]              [♡ 2] [···]
     댓글 내용
  🔵 익명1                         [♡ 1] [···]
     댓글 내용
     └ 🔵 익명2 (대댓글)           [♡ 0] [···]
  🔵 익명1  [나]                   [♡ 0] [···]
     내가 쓴 댓글 (나 뱃지 표시)
──────────────────────────────────────────
[👤] [텍스트 입력창          ] [전송]
```

**스레드 익명화 레이블:**
- 게시글 작성자가 익명 댓글 → "글쓴이" 표시
- 그 외 익명 댓글 → "익명1", "익명2" (최초 등장 순)
- 본인 댓글 → "나" 뱃지 추가 표시

**더보기 액션 시트 (본인 게시글):**
- 수정
- 삭제 (빨강)

**더보기 액션 시트 (타인 게시글):**
- 대화하기
- 게시물/회원 신고하기 → 카테고리 다이얼로그
- 이 회원의 글 모두 숨기기

**댓글 더보기 액션 시트:**
- 대화하기 (타인 댓글, 비익명일 때만)
- 댓글/회원 신고하기 → 카테고리 다이얼로그
- 이 회원의 글 모두 숨기기
- 삭제 (본인 댓글만)

### 6-4. 글쓰기 화면 (post_write_screen)

```
AppBar: "글쓰기"                                [등록]
─────────────────────────────────────────────────────────
제목 입력
────────────────
본문 입력 (Expanded)

[전체 게시판일 때만 표시]
@태그로 대상 지정
  [@기장군] [@부산중앙고등학교] [@1학년]  ← FilterChip 선택

────────────────
🔘 익명으로 게시
```

### 6-5. 신고 카테고리 다이얼로그 (공통 컴포넌트 — showReportDialog)

```
┌─────────────────────────────────────┐
│ 신고하기                            │
│ 신고 사유를 선택해주세요.            │
│                                     │
│ ◯  스팸/홍보                        │
│ ◯  음란/선정적 내용                 │
│ ◯  욕설/비방/혐오                   │
│ ◯  개인정보 노출                    │
│ ◯  허위 사실/명예훼손               │
│ ◯  불법 정보 (마약/도박 등)         │
│ ◯  주제와 무관한 게시물             │
│ ◉  기타                             │
│   ┌────────────────────────────┐    │
│   │ 기타 사유를 입력하세요     │    │
│   └────────────────────────────┘    │
│                                     │
│              [취소]  [신고]          │
└─────────────────────────────────────┘
```

### 6-6. 검색 화면 (search_screen)

```
AppBar: [🔍 게시글 검색__________] [✕]
─────────────────────────────────────────────────────────
결과 목록: 게시글 제목 + 좋아요/댓글 수
```

### 6-7. DM 화면 (dm_list_screen + dm_chat_screen)

**목록 (SSE 실시간 연결):**
```
AppBar: "대화"
─────────────────────────────────────────────────────────
🔵 닉네임A                          MM.DD HH:mm   [3]
   마지막 메시지 미리보기... (미읽 시 굵은 글씨)
─────────────────────────────────────────────────────────
🔵 닉네임B                          MM.DD HH:mm
   마지막 메시지 미리보기...
```

**채팅:**
```
AppBar: 상대방닉네임
─────────────────────────────────────────────────────────
                        상대 메시지 (좌측, 회색 말풍선)
나의 메시지 (우측, Primary 색상 말풍선)
                                              HH:mm

[메시지 입력창                                  ] [전송]
```

### 6-8. 프로필 화면 (profile_screen)

- 닉네임, 지역, 학교명, 학년, 매너온도 표시
- 내 게시글 목록
- 스크랩 목록
- 로그아웃

---

## 7. 게시판 구조

### 7-1. board_type 종류

| board_type | 탭 표시명 | 접근 범위 |
|-----------|----------|----------|
| `region` | 지역명 (예: 기장군) | 동일 `region` 유저들의 글 |
| `school` | 학교명 (예: 부산중앙고등학교) | 동일 `school_code` 유저들의 글 |
| `grade` | N학년 | 동일 학교 + 동일 학년 |
| `free` | 전체 | 모든 글 (학교 필터 없음) |

### 7-2. @태그 (mention_tags) 시스템

- `free` 게시판 글 작성 시 `@기장군`, `@부산중앙고등학교`, `@1학년` 등 태그 선택
- 태그 저장 형식: `["region:기장군", "school:B100000011", "grade:1"]`
- 조회 시 현재 유저의 프로필과 매칭되는 태그가 있는 글을 **상단** 정렬 (Python-side 정렬)
- 앱에서 매칭된 게시글에 **[추천]** 배지 표시

### 7-3. 게시글 작성 가능 게시판

| 게시판 | 조건 |
|--------|------|
| 지역 | 해당 지역 인증 유저 |
| 학교 | 해당 학교 인증 유저 |
| 학년 | 해당 학교 + 학년 인증 유저 |
| 전체 | 모든 인증 유저 |

---

## 8. 신고 시스템

### 8-1. 현재 구현 상태

- 신고 대상: 게시글(post) / 댓글(comment)
- 동일 유저의 동일 대상 중복 신고 차단 (DB UNIQUE 제약)
- **8가지 카테고리 선택 + 기타 사유 직접 입력** (Flutter 라디오버튼 다이얼로그)
- 누적 5건 → `is_hidden = True` 자동 블라인드
- 신고 상태 관리: `pending → reviewed → dismissed / actioned`

### 8-2. 신고 카테고리

| 코드 | 표시명 | 설명 |
|------|--------|------|
| `SPAM` | 스팸/홍보 | 광고, 도배, 반복 게시 |
| `OBSCENE` | 음란/선정적 내용 | 성적 표현, 부적절한 콘텐츠 |
| `ABUSE` | 욕설/비방/혐오 | 특정인 공격, 혐오 표현 |
| `PERSONAL_INFO` | 개인정보 노출 | 연락처, 주소, 실명 등 |
| `MISINFORMATION` | 허위 사실/명예훼손 | 학교·교육 관련 거짓 정보 |
| `ILLEGAL` | 불법 정보 | 마약, 도박, 법령 위반 |
| `OFF_TOPIC` | 주제와 무관한 게시물 | 게시판 성격과 맞지 않는 글 |
| `OTHER` | 기타 | 위 항목 해당 없음 (직접 입력 필수) |

### 8-3. 신고 처리 절차 (설계 — 관리자 시스템 구현 후 적용)

```
신고 접수 (POST /posts/report)
    │
    ├─ [중복 신고] → 400 오류
    │
    ▼
report_count 증가 + reports 테이블 기록
    │
    ├─ 1~4건: 기록만
    ├─ 3건:   관리자 검토 대기열 등록 (알림)
    ├─ 5건:   is_hidden = True (자동 블라인드)
    │          작성자 FCM 알림: "신고 누적으로 게시글이 숨김 처리되었습니다."
    └─ 10건:  긴급 처리 플래그

관리자 검토 (reports.status = 'reviewed')
    │
    ├─ [정상 판단] → is_hidden = False 복원
    │               허위 신고자 경고 1회 자동 부여
    │
    └─ [위반 판단] → 게시글/댓글 영구 삭제
                     작성자 조치 (user_warnings 기록):
                     경고 1회: 앱 알림
                     경고 2회: 7일 정지 (suspended_until = now + 7d)
                     경고 3회: 30일 정지
                     경고 5회 or 중대 위반: 영구 정지 (is_banned = True)
```

---

## 9. 차단 및 숨기기

### 현재 구현

- `POST /users/{target_id}/block` — 차단 등록
- `DELETE /users/{target_id}/block` — 차단 해제
- 게시글 목록 조회 시 차단된 유저의 게시글 자동 필터링
- 익명 게시글은 `author_id` 식별 불가로 차단 불가 (앱에서 안내 메시지)

### 보완 필요

| 항목 | 설명 |
|------|------|
| 댓글 차단 필터링 | 현재 게시글만 필터, 댓글은 미적용 |
| 차단 목록 조회 | `GET /users/blocks` 미구현 |
| DM 차단 연동 | 차단된 유저에게 DM 발신 불가 처리 |

---

## 10. 1:1 대화 (DM)

### 현재 구현

- 게시글/댓글 더보기 → "대화하기" → 대화방 자동 생성(또는 기존 반환)
- 메시지 목록 조회 시 자동 읽음 처리
- 대화 목록: 마지막 메시지 미리보기 + 안 읽은 메시지 수 배지
- **SSE 실시간 수신**: 새 메시지 도착 시 대화 목록 자동 갱신
- **FCM 푸시**: 앱 백그라운드/종료 상태에서도 수신 알림

### 보완 필요

| 항목 | 설명 |
|------|------|
| 익명 DM | 익명 게시글 작성자에게 DM 불가 → 익명 DM 옵션 설계 필요 |
| 차단 연동 | 차단된 유저에게 DM 발신 차단 |
| 메시지 삭제 | 발송된 메시지 삭제 기능 없음 |
| DM 신고 | DM 내용 신고 기능 없음 |
| 채팅방 SSE | 목록만 실시간, 채팅방 내부는 전송 후 자동 갱신 방식 |

---

## 11. 계정 정지 시스템

### 현재 구현

**계정 상태 판단 순서 (`GET /api/v1/...` 전체 적용):**

```
get_current_user 의존성 주입 단계에서 순차 검증:
  1. JWT 유효성 검사 → 실패 시 401
  2. 유저 존재 여부 → 없으면 401
  3. is_banned == True → 403 "영구 정지된 계정입니다."
  4. suspended_until > now → 403 "계정이 정지되었습니다. 해제 시각: {datetime}"
     (응답 헤더 X-Suspend-Until: ISO 8601 시각 포함)
  5. 정상 → 유저 객체 반환
```

**정지 유형:**

| 유형 | 컬럼 | 해제 방법 |
|------|------|----------|
| 기간 정지 | `suspended_until` (DateTime) | 해제 시각 경과 시 자동 해제 |
| 영구 정지 | `is_banned` (Boolean) | 관리자 수동 해제만 가능 |

**경고 누적 처리 (user_warnings 테이블 기록):**

| warning_type | 처리 내용 |
|------|------|
| `warning` | 경고 1회, 앱 알림 |
| `suspend_7d` | suspended_until = now + 7일 |
| `suspend_30d` | suspended_until = now + 30일 |
| `banned` | is_banned = True (영구) |

---

## 12. 스레드 익명화

### 설계 원칙

- **서버 런타임 계산** — DB에 저장하지 않음 (게시글 삭제/복원 등 상태 변화에 강건)
- 같은 게시글 내에서만 유효한 레이블 (게시글 간 연결 없음)
- 복호화 불가 — 외부에서 실제 `author_id` 유추 불가

### 레이블 규칙

| 조건 | 표시 레이블 |
|------|------------|
| 익명 댓글 + 게시글 작성자 본인 | "글쓴이" |
| 익명 댓글 + 최초 등장 타인 | "익명1" |
| 익명 댓글 + 두 번째 등장 타인 | "익명2" |
| 비익명 댓글 | 닉네임 표시 (`author_nickname`) |
| 본인이 작성한 댓글 | `is_mine: true` → "나" 뱃지 추가 |

### API 응답 필드 (`CommentResponse`)

```json
{
  "id": 42,
  "content": "댓글 내용",
  "is_anonymous": true,
  "anon_label": "익명1",       ← 서버가 계산한 표시명
  "is_mine": false,             ← 현재 요청 유저가 작성자인지
  "is_post_author": false,      ← 댓글 작성자 == 게시글 작성자 여부
  "like_count": 3,
  "is_liked": false,
  "created_at": "2026-06-20T10:00:00"
}
```

---

## 13. 금칙어 필터링

### 구현 위치

`backend/app/core/profanity.py`

### 동작 방식

```
게시글/댓글 저장 요청
    ↓
check_profanity(제목) + check_profanity(내용)
    ↓
금칙어 포함 시: ValueError → 400 Bad Request
    "제목/내용에 사용할 수 없는 단어가 포함되어 있습니다."
    ↓
정상 시: DB 저장 진행
```

### 금칙어 관리

| 방법 | 설명 |
|------|------|
| 기본 목록 | 코드 내 하드코딩 (욕설/혐오 표현 핵심 단어) |
| 운영자 추가 | `PROFANITY_WORDS` 환경변수 (쉼표 구분) — 서버 재시작 필요 |
| 향후 개선 | DB 테이블로 관리 + 관리자 대시보드에서 실시간 추가/삭제 |

### 적용 범위

| 위치 | 검사 대상 |
|------|----------|
| `post_service.create_post` | 제목 + 본문 |
| `comment_service.create_comment` | 댓글 내용 |
| 게시글 수정 | 미적용 (보완 필요) |

---

## 14. 푸시 알림 (FCM)

### 구현 현황

**백엔드 (`backend/app/core/fcm.py`):**
- Firebase Admin SDK 연동 (선택적 — `FCM_SERVICE_ACCOUNT_JSON` 미설정 시 graceful skip)
- 발송 실패 시 예외 전파 없이 경고 로그만 기록 (서비스 영향 없음)

**FCM 토큰 등록:**
- `POST /auth/me/fcm-token` — 앱 시작 시 기기 토큰 서버에 저장/갱신
- `users.fcm_token` 컬럼에 1기기 1토큰 관리 (멀티 기기 미지원)

**알림 발송 시점:**

| 이벤트 | 수신자 | 알림 내용 |
|--------|--------|----------|
| 내 게시글에 댓글 | 게시글 작성자 | "새 댓글이 달렸어요: {댓글 내용 50자}" |
| DM 수신 | DM 수신자 | "{닉네임}님의 메시지: {내용 80자}" |

**알림 payload (`data` 필드):**

```json
// 댓글 알림
{"type": "comment", "post_id": "123"}

// DM 알림
{"type": "dm", "conversation_id": "456"}
```

### 활성화 방법

1. Firebase Console → 프로젝트 설정 → 서비스 계정 → "새 비공개 키 생성"
2. 다운로드된 JSON 파일 내용을 `.env`에 한 줄로:
   ```
   FCM_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"..."}
   ```
3. `pubspec.yaml`에 `firebase_messaging` 패키지 추가 (현재 미추가)
4. `board_screen.dart`의 `_tryGetMessaging()`에서 `FirebaseMessaging.instance` 반환하도록 수정

---

## 15. 실시간 DM (SSE)

### 설계

```
클라이언트                          서버
    │                                │
    │  GET /api/v1/stream            │
    │  Authorization: Bearer {token} │
    │ ──────────────────────────────▶│
    │                                │ asyncio.Queue 생성 (user_id 기준)
    │  data: {"type":"connected"}    │
    │ ◀──────────────────────────────│
    │                                │
    │          (다른 사용자가 DM 발송)
    │                                │ Queue에 이벤트 push
    │  data: {"type":"new_message",  │
    │    "conversation_id": 5,       │
    │    "sender_id": 12,            │
    │    "content": "안녕하세요",    │
    │    "created_at": "2026-..."}   │
    │ ◀──────────────────────────────│
    │                                │
    │  (25초 무활동 시)               │
    │  : heartbeat                   │
    │ ◀──────────────────────────────│
```

### 구현 상세

**서버 (`backend/app/core/sse_manager.py`):**
- `user_id → set[asyncio.Queue]` 인메모리 딕셔너리
- 동일 유저 다중 탭/기기 지원 (큐 복수 생성)
- 25초 heartbeat (nginx 등 프록시 연결 유지)
- **주의**: 단일 인스턴스 전용. 멀티 인스턴스 배포 시 Redis Pub/Sub으로 교체 필요

**클라이언트 (`dm_list_screen.dart`):**
- `http` 패키지로 스트림 연결 (EventSource 미지원 Flutter 환경 대응)
- `new_message` 이벤트 수신 시 대화 목록 자동 갱신 (unread_count 포함)
- 연결 끊김 시 5초 후 자동 재연결

**DM 발송 → SSE 이벤트 + FCM 동시 처리:**
```
POST /conversations/{id}/messages
    ↓
DirectMessage DB 저장
    ↓
sse_manager.publish(recipient_id, "new_message", {...})  ← SSE (앱 포그라운드)
    ↓
send_push(recipient.fcm_token, ...)                       ← FCM (앱 백그라운드/종료)
```

---

## 16. 보안 설계

### 16-1. 현재 구현된 보안 항목

| 항목 | 상태 | 설명 |
|------|------|------|
| 전화번호 비저장 | ✅ | 서비스 DB에 전화번호 없음 |
| HMAC 익명화 | ✅ | SHA256 + 별도 시크릿키 (`ANON_HASH_SECRET`) |
| JWT Bearer 인증 | ✅ | 모든 API 엔드포인트 필수 |
| Access Token 만료 | ✅ | 60분 |
| Refresh Token 만료 | ✅ | 30일 |
| 자동 토큰 갱신 | ✅ | Dio 인터셉터 (401 시 자동 재발급 후 재시도) |
| CORS 설정 | ✅ | `ALLOWED_ORIGINS` 화이트리스트 |
| 본인 게시글만 수정/삭제 | ✅ | `author_id == user.id` 서버 검증 |
| 중복 신고 차단 | ✅ | DB UNIQUE 제약 |
| 중복 좋아요 차단 | ✅ | DB UNIQUE 제약 |
| SMS 인증코드 TTL | ✅ | 5분 만료 |
| Soft Delete | ✅ | `is_deleted` 플래그 |
| 영구 정지 차단 | ✅ | `is_banned` 검증 → 403 |
| 기간 정지 차단 | ✅ | `suspended_until` 검증 → 403 + 해제시각 헤더 |
| 서버 금칙어 필터 | ✅ | 게시글/댓글 저장 시 검사 → 400 |
| 신고 카테고리 검증 | ✅ | 허용된 카테고리 코드만 수용 |

### 16-2. 보완 필요 보안 항목

| 항목 | 우선순위 | 설명 |
|------|----------|------|
| Rate Limiting | 🔴 높음 | SMS API 남용, 게시글 도배 방지 (Redis 슬라이딩 윈도우) |
| HTTPS 강제 | 🔴 높음 | 프로덕션에서 TLS 종단 (Nginx + Let's Encrypt) |
| 토큰 블랙리스트 | 🟡 중간 | 로그아웃 시 Refresh Token 무효화 (Redis 필요) |
| 학교 인증 재검증 | 🟡 중간 | 졸업/전학 시 연 1회 NEIS 재인증 강제 |
| 입력값 길이 검증 | 🟡 중간 | `content` 컬럼 최대 길이 미설정 (Text 무제한) |
| 게시글 수정 금칙어 | 🟡 중간 | 현재 수정 시 금칙어 검사 미적용 |
| 개인정보 마스킹 로그 | 🟡 중간 | 서버 로그에 anon_id 노출 최소화 |
| DDoS 방어 | 🔵 낮음 | CloudFront 또는 WAF |
| Certificate Pinning | 🔵 낮음 | 모바일 배포 시 앱 위변조 방지 |
| 이미지 업로드 보안 | 🔵 낮음 | 파일 타입 검증, 바이러스 스캔 (미구현) |

### 16-3. 프로덕션 체크리스트

```
□ SECRET_KEY: 64자 이상 랜덤 문자열로 변경
□ ANON_HASH_SECRET: SECRET_KEY와 완전히 다른 값으로 설정
□ DEBUG=false
□ ALLOWED_ORIGINS: 실제 도메인만 허용
□ FCM_SERVICE_ACCOUNT_JSON: Firebase 서비스 계정 JSON 설정
□ PostgreSQL 비밀번호 강화
□ Redis AUTH 설정
□ DB 백업 정책 수립 (RDS 자동 스냅샷 등)
□ HTTPS 인증서 설정 (Nginx + Let's Encrypt)
□ 로그 수집 설정 (ELK 또는 CloudWatch)
□ SSE 멀티 인스턴스 배포 시 Redis Pub/Sub으로 sse_manager 교체
```

---

## 17. 관리자 시스템 (설계안 — 미구현)

### 17-1. 관리자 역할 설계

| 역할 | 권한 |
|------|------|
| `super_admin` | 모든 권한 (관리자 계정 생성/삭제 포함) |
| `admin` | 신고 처리, 게시글/댓글 삭제, 계정 정지/해제 |
| `moderator` | 신고 검토, 게시글/댓글 블라인드 (삭제 불가) |

### 17-2. 관리자 DB 테이블 (설계안)

```sql
-- 관리자 계정 (별도 Admin DB 권장)
admin_users:
  id            INT PK
  email         VARCHAR(100) UNIQUE
  password_hash VARCHAR(200)
  role          VARCHAR(20)   -- super_admin / admin / moderator
  is_active     BOOLEAN
  last_login_at DATETIME

-- 관리자 처리 로그 (감사 추적)
admin_actions:
  id            INT PK
  admin_id      FK → admin_users
  action_type   VARCHAR(30)   -- hide_post / delete_post / warn_user / suspend / ban / unban / dismiss_report
  target_type   VARCHAR(20)   -- post / comment / user / report
  target_id     INT
  note          TEXT          -- 처리 사유
  created_at    DATETIME
```

### 17-3. 관리자 API 설계안

| Method | Path | 권한 | 설명 |
|--------|------|------|------|
| GET | `/admin/reports?status=pending&category=` | moderator+ | 신고 대기 목록 (카테고리 필터) |
| GET | `/admin/reports/{id}` | moderator+ | 신고 상세 (원문 포함) |
| POST | `/admin/reports/{id}/dismiss` | moderator+ | 신고 기각 |
| POST | `/admin/reports/{id}/action` | admin+ | 경고/정지/삭제 처리 |
| GET | `/admin/users?q=` | admin+ | 유저 검색 |
| GET | `/admin/users/{id}` | admin+ | 유저 상세 (경고 이력 포함) |
| POST | `/admin/users/{id}/warn` | admin+ | 경고 1회 부여 |
| POST | `/admin/users/{id}/suspend` | admin+ | 기간 정지 (days 파라미터) |
| POST | `/admin/users/{id}/ban` | admin+ | 영구 정지 |
| POST | `/admin/users/{id}/unban` | admin+ | 정지 해제 |
| DELETE | `/admin/posts/{id}` | admin+ | 게시글 강제 삭제 |
| POST | `/admin/posts/{id}/hide` | moderator+ | 게시글 블라인드 |
| POST | `/admin/posts/{id}/unhide` | moderator+ | 블라인드 해제 |
| GET | `/admin/profanity` | admin+ | 금칙어 목록 조회 |
| POST | `/admin/profanity` | admin+ | 금칙어 추가 |
| DELETE | `/admin/profanity/{word}` | admin+ | 금칙어 삭제 |

### 17-4. 관리자 대시보드 항목 (향후 구현)

- 오늘/주간/월간 신고 건수 (카테고리별)
- 처리 대기 신고 목록
- 유저 경고/정지 이력
- 금칙어 실시간 관리
- 가입 추이 그래프

---

## 18. 미구현 / 보완 필요 항목

### 우선순위 높음 🔴

| 항목 | 설명 |
|------|------|
| 관리자 시스템 | DB 테이블, API, 대시보드 전무 — 신고 처리 플로우 실질 미완성 |
| Rate Limiting | SMS/게시글 API 남용 방어 (Redis 슬라이딩 윈도우) |
| 게시글 수정 금칙어 검사 | 현재 작성 시만 검사, 수정 시 미적용 |
| 댓글 차단 필터링 | 게시글만 필터링, 댓글은 미적용 |

### 우선순위 중간 🟡

| 항목 | 설명 |
|------|------|
| Firebase 앱 설정 | `firebase_messaging` 패키지 미추가, `_tryGetMessaging()` 스텁 상태 |
| 멀티 기기 FCM | 현재 기기 1개 (마지막 등록 토큰만 유지) |
| SSE 멀티 인스턴스 | 인메모리 큐 → Redis Pub/Sub 전환 필요 |
| 채팅방 내 SSE | 목록만 실시간, 채팅방 내부는 미적용 |
| 이미지 첨부 | S3 presigned URL 방식 — 코드 뼈대 없음 |
| 알림 탭 | 댓글 알림, 신고 알림 등 인앱 알림 목록 없음 |
| 차단 목록 조회 | `GET /users/blocks` 미구현 |
| 차단 DM 연동 | 차단된 유저에게 DM 발신 가능 (차단 미연동) |
| 토큰 블랙리스트 | 로그아웃 시 Refresh Token 무효화 미구현 |
| 학교 인증 재검증 | 졸업/전학 시 연 1회 NEIS 재인증 강제 미구현 |
| 게시판 정렬 옵션 | 최신순만, 인기순/조회수순 미구현 |
| 무한 스크롤 | 현재 고정 20개 반환 |

### 우선순위 낮음 🔵

| 항목 | 설명 |
|------|------|
| iOS/Android 빌드 | 현재 Flutter Web만 테스트 |
| 앱 아이콘/스플래시 | 기본값 사용 |
| 오프라인 캐싱 | 없음 |
| 검색 고도화 | 현재 ILIKE 단순 검색, 전문 검색엔진 미도입 |
| 공유하기 | 게시글 외부 공유 없음 |
| 이미지 갤러리 | 게시글 내 이미지 없음 |
| 매너온도 시스템 | 컬럼은 있으나 변동 로직 없음 |
| 다크 모드 | 미지원 |
| 금칙어 DB 관리 | 현재 환경변수 기반, DB + 관리자 UI 필요 |

---

## 19. 인프라 및 배포

### 19-1. 현재 Docker Compose 구성

| 서비스 | 이미지 | 포트 | 역할 |
|--------|--------|------|------|
| `momstalk_backend` | Python 3.12 | 8000 | FastAPI 앱 |
| `momstalk_service_db` | PostgreSQL | 5432 | 서비스 DB |
| `momstalk_auth_db` | PostgreSQL | 5433 | 인증 DB |
| `momstalk_redis` | Redis | 6379 | 캐시 (현재 미활용) |

### 19-2. 환경변수 (.env)

```ini
# DB
DATABASE_URL=postgresql+asyncpg://...@db_service:5432/momstalk_db
AUTH_DATABASE_URL=postgresql+asyncpg://...@db_auth:5432/momstalk_auth_db
REDIS_URL=redis://redis:6379/0

# 보안
SECRET_KEY={64자 이상 랜덤}
ANON_HASH_SECRET={SECRET_KEY와 다른 값}

# NEIS
NEIS_API_KEY={교육부 나이스 오픈API 키}

# SMS
SMS_API_KEY=
SMS_API_SECRET=
SMS_SENDER=

# FCM
FCM_SERVICE_ACCOUNT_JSON={Firebase 서비스 계정 JSON 한 줄}

# 앱
DEBUG=true   # 프로덕션: false
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8081
PROFANITY_WORDS=  # 추가 금칙어 (쉼표 구분)
```

### 19-3. DB 마이그레이션 이력

| 버전 | 내용 |
|------|------|
| 0001 | `posts.mention_tags` JSON 컬럼 추가 |
| 0002 | `blocks`, `conversations`, `direct_messages` 테이블 추가 |
| 0003 | `users.suspended_until`, `users.warning_count`, `reports` 카테고리 컬럼 추가, `user_warnings` 테이블 추가 |
| 0004 | `users.fcm_token` 컬럼 추가 |

### 19-4. 향후 프로덕션 인프라 설계안

```
사용자 앱
    │ HTTPS
┌───▼──────────────┐
│   CloudFront     │  CDN + DDoS 기본 방어
└───┬──────────────┘
    │
┌───▼──────────────┐
│   Nginx          │  리버스 프록시 + TLS 종단
│                  │  SSE: proxy_buffering off;
│                  │        proxy_read_timeout 3600s;
└───┬──────────────┘
    │
┌───▼──────────────┐
│  FastAPI × N     │  컨테이너 수평 확장
│                  │  ※ SSE 멀티 인스턴스 시
│                  │    Redis Pub/Sub 필요
└───┬──────────────┘
    │
┌───▼──────────────────────────────────┐
│  RDS PostgreSQL × 2 (Multi-AZ)      │
│  ElastiCache Redis (Rate Limit,      │
│                     토큰 블랙리스트, │
│                     SSE Pub/Sub)     │
└──────────────────────────────────────┘
```

> **SSE + Nginx 주의사항**: SSE 엔드포인트(`/api/v1/stream`)는 Nginx 설정에서 `proxy_buffering off`와 충분한 `proxy_read_timeout`이 필요합니다. `X-Accel-Buffering: no` 응답 헤더를 서버에서 이미 설정하고 있습니다.

---

*이 문서는 2026-06-20 기준 구현 상태를 반영합니다. 미구현 항목은 [18절](#18-미구현--보완-필요-항목)을 참조하세요.*
