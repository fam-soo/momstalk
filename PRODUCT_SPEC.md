# MomsTalk (맘스톡크) — 제품 사양서 및 개발 현황 문서

> 작성 기준일: 2026-06-27  
> 현재 버전: v0.4.2  
> 플랫폼: Flutter Web PWA (출시 우선) → iOS (MAU 5,000 달성 시) → Android (12개월~)  
> 백엔드: FastAPI + PostgreSQL × 2 + Redis  
> 사업계획서 기준: v1.0 (2026년 7월)

---

## 목차

1. [서비스 개요](#1-서비스-개요)
2. [아키텍처 설계](#2-아키텍처-설계)
3. [인증 및 계정 설계](#3-인증-및-계정-설계)
4. [DB 스키마 상세](#4-db-스키마-상세)
5. [API 엔드포인트 목록](#5-api-엔드포인트-목록)
6. [화면 구성 및 UI 레이아웃](#6-화면-구성-및-ui-레이아웃)
7. [게시판 구조 — 선택적 실명제](#7-게시판-구조--선택적-실명제)
8. [학원 후기 시스템](#8-학원-후기-시스템)
9. [신고 시스템](#9-신고-시스템)
10. [차단 및 숨기기](#10-차단-및-숨기기)
11. [1:1 대화 (DM)](#11-11-대화-dm)
12. [계정 정지 시스템](#12-계정-정지-시스템)
13. [스레드 익명화](#13-스레드-익명화)
14. [금칙어 필터링](#14-금칙어-필터링)
15. [푸시 알림 (FCM)](#15-푸시-알림-fcm)
16. [실시간 DM (SSE)](#16-실시간-dm-sse)
17. [보안 설계](#17-보안-설계)
18. [관리자 시스템 — Streamlit 대시보드](#18-관리자-시스템--streamlit-대시보드)
19. [수익화 모델](#19-수익화-모델)
20. [로드맵 및 KPI](#20-로드맵-및-kpi)
21. [미구현 / 보완 필요 항목](#21-미구현--보완-필요-항목)
22. [인프라 및 배포](#22-인프라-및-배포)

---

## 1. 서비스 개요

**MomsTalk(맘스톡크)**는 NEIS 학교 인증 기반의 학부모 전용 교육 정보 커뮤니티 플랫폼이다.  
기존 맘카페의 폐쇄성·허위 후기 문제를 해결하고, 지역×학교급×과목으로 구조화된 학원 후기 DB와 선택적 실명제를 결합하여 신뢰할 수 있는 **하이퍼로컬 교육 정보 허브**를 구축한다.

### 핵심 원칙

| 원칙 | 설명 |
|------|------|
| **선택적 실명제** | 학원 후기·입시 정보는 인증 닉네임으로, 민감 고민은 완전 익명으로 분리 운영 |
| **NEIS 학교 인증** | 교육부 나이스 API 기반 실제 학교 인증 → 학부모 신뢰도 보장 |
| **이중 DB 분리** | 전화번호(신원) DB ↔ 활동 DB 물리적 분리 → 역추적 원천 차단 |
| **구조화 학원 DB** | NEIS 학원 목록 선구축 + 5항목 정형 리뷰 템플릿 → Cold Start 방어 |
| **자동 중재** | 신고 5건 누적 자동 블라인드, Streamlit 관리자 대시보드로 1인 운영 최적화 |
| **스레드 익명화** | 같은 게시글 내 댓글 "글쓴이/익명1/익명2…" 레이블로 익명성 유지 |
| **실시간 알림** | FCM 푸시 + SSE DM 실시간 수신 |

### 포지셔닝

| 플랫폼 | 한계 | MomsTalk 차별점 |
|--------|------|----------------|
| 네이버 맘카페 | 텃세·여론통제·광고 후기 난무 | NEIS 인증 + 선택적 실명제로 신뢰 확보 |
| 밴드(카카오) | 폐쇄 그룹, 공개 학원 DB 없음 | 지역×학교급×과목 구조화 리뷰 |
| 클래스팅 | B2B 중심, 학부모 커뮤니티 기능 없음 | 양방향 커뮤니티 + 학원 후기 |

---

## 2. 아키텍처 설계

```
┌──────────────────────────────────────────────────────────┐
│  Flutter App (Web PWA 우선 → iOS → Android)              │
│  ┌──────────────┐ ┌──────────┐ ┌─────────────────────┐  │
│  │ 게시판 탭    │ │ 학원 탭  │ │ 대화(DM) 탭         │  │
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
│  /api/v1/schools/*      NEIS 학교·학원 검색              │
│  /api/v1/posts/*        게시글/댓글/신고                 │
│  /api/v1/academies/*    학원 프로필 + 후기               │
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
│             │  (단방향)     │ 학원 후기      │
└─────────────┘               │ 좋아요/스크랩  │
                              │ DM/차단/신고   │
                              │ 경고 이력      │
                              └────────────────┘
                                     │
                              ┌──────▼─────┐
                              │   Redis    │
                              │  :6379     │
                              │ Rate Limit │
                              │ 토큰 블랙  │
                              │ 리스트     │
                              └────────────┘
                                     │
                              ┌──────▼─────────┐
                              │  Streamlit     │
                              │  Admin 대시보드 │
                              │  (내부 전용)   │
                              └────────────────┘
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
| 관리자 도구 | Streamlit (신고처리·경고·금칙어 관리) |
| 컨테이너 | Docker Compose → AWS ECS (Phase 3) |

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
닉네임 자동 생성:
  인증 닉네임: "{학교약칭}_{형용사}{명사}" (예: 행복초_지혜맘)
  익명 닉네임: "{형용사}{명사}{4자리숫자}" (예: 지혜로운학부모4712)
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
| 인증 닉네임 | `certified_nickname` — 학교 인증 기반 고정 닉네임. 학원 후기·입시 게시판에서 사용 |
| 익명 닉네임 | `anon_nickname` — 민감 고민 게시판에서 사용. 게시글마다 표시 여부 선택 |

### 3-3. 계정 필드 (Service DB — `users` 테이블)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | 서비스 내부 식별자 |
| `anon_id` | String(64) UNIQUE | HMAC 해시값 |
| `anon_nickname` | String(30) | 완전 익명용 자동 생성 닉네임 (예: 지혜로운학부모4712) |
| `certified_nickname` | String(50) | 인증 닉네임 (예: 행복초_지혜맘) — 학원/입시 게시판 노출 |
| `region` | String(30) | 지역 (예: 기장군) |
| `school_code` | String(20) | NEIS 학교 코드 |
| `school_name` | String(100) | 학교명 |
| `school_short_name` | String(20) | 학교 약칭 (인증 닉네임 생성용) |
| `grade` | Integer | 학년 |
| `class_num` | Integer | 반 |
| `school_type` | String(10) | elementary / middle / high |
| `manner_score` | Integer | 매너온도 (초기값 36) |
| `fcm_token` | String(256) | Firebase 푸시 토큰 |
| `is_banned` | Boolean | 영구 정지 여부 |
| `suspended_until` | DateTime | 기간 정지 해제 시각 |
| `warning_count` | Integer | 누적 경고 횟수 |
| `profile_updated_at` | DateTime | 프로필 최종 수정일 (월 1회 제한용) |

### 3-4. 닉네임 자동 생성 규칙

| 유형 | 형식 | 예시 |
|------|------|------|
| 인증 닉네임 | `{학교약칭}_{형용사}{명사}` | `행복초_지혜맘`, `중앙중_용감한아빠` |
| 익명 닉네임 | `{형용사}{명사}{4자리숫자}` | `지혜로운학부모4712`, `용감한아빠0031` |

---

## 4. DB 스키마 상세

### Service DB 테이블 목록

#### `users` — 유저

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | |
| `anon_id` | String(64) UNIQUE | HMAC 해시, 신원 역추적 불가 |
| `anon_nickname` | String(30) | 완전 익명용 자동 생성 |
| `certified_nickname` | String(50) | 인증 닉네임 (학원/입시 게시판) |
| `region` | String(30) | 지역 |
| `school_code` | String(20) | NEIS 학교 코드 |
| `school_name` | String(100) | |
| `school_short_name` | String(20) | 학교 약칭 |
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
| `board_type` | String(20) | region / school / grade / free / academy_review / entrance |
| `nickname_type` | String(10) | **certified** (인증 닉네임) / **anon** (익명) — 게시글별 선택 |
| `school_code` | String(20) | 게시글 작성 시 소속 학교 |
| `grade` | Integer | grade 게시판에서만 사용 |
| `title` | String(200) | 2~200자 |
| `content` | Text | 5자 이상 |
| `is_anonymous` | Boolean | 익명 여부 (nickname_type=anon일 때 true) |
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
| `nickname_type` | String(10) | certified / anon |
| `is_anonymous` | Boolean | |
| `like_count` | Integer | |
| `report_count` | Integer | |
| `is_hidden` | Boolean | |
| `is_deleted` | Boolean | |
| `created_at` | DateTime | |

#### `academies` — 학원 프로필 (신규)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | |
| `neis_academy_code` | String(20) UNIQUE | NEIS 학원 코드 |
| `name` | String(100) | 학원명 |
| `region` | String(30) | 지역 |
| `address` | String(200) | 주소 |
| `subjects` | JSON | 과목 목록 (예: ["수학", "영어"]) |
| `school_type` | String(10) | elementary / middle / high / all |
| `phone` | String(20) | 전화번호 (nullable) |
| `is_b2b` | Boolean | B2B 유료 프로필 여부 (기본값 false) |
| `b2b_expires_at` | DateTime | B2B 구독 만료일 (nullable) |
| `review_count` | Integer | 후기 수 |
| `avg_rating` | Float | 평균 평점 |
| `created_at` | DateTime | |

#### `academy_reviews` — 학원 후기 (신규)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | |
| `academy_id` | FK → academies | |
| `author_id` | FK → users | |
| `subject` | String(30) | 수강 과목 |
| `teacher_style` | String(10) | strict / free / careful (엄격형/자유형/꼼꼼형) |
| `homework_level` | Integer | 1~3 (★ 개수) |
| `score_improvement` | String(20) | much_up / up / same / down |
| `review_text` | String(200) | 100자 이내 총평 |
| `rating` | Integer | 1~5 별점 |
| `is_anonymous` | Boolean | 익명 여부 (인증 닉네임/완전 익명 선택) |
| `report_count` | Integer | |
| `is_hidden` | Boolean | |
| `created_at` | DateTime | |
| UNIQUE | (author_id, academy_id, subject) | 동일 학원·과목 중복 후기 방지 |

#### `likes` — 좋아요

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `user_id` | FK → users | |
| `target_type` | String(10) | post / comment / academy_review |
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
| `target_type` | String(10) | post / comment / academy_review |
| `target_id` | Integer | |
| `category` | String(20) | 신고 카테고리 코드 (8가지) |
| `reason` | String(200) | 기타 사유 (category=OTHER일 때) |
| `status` | String(20) | pending / reviewed / dismissed / actioned |
| `reviewed_by` | Integer | 관리자 user_id (nullable) |
| `reviewed_at` | DateTime | |
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
| 0005 | `users.certified_nickname`, `users.school_short_name` 추가, `posts.nickname_type` 추가 (예정) |
| 0006 | `academies`, `academy_reviews` 테이블 추가 (예정) |

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
| DELETE | `/auth/me` | 회원 탈퇴 |

### 학교·학원 검색 (schools)

| Method | Path | 설명 |
|--------|------|------|
| GET | `/schools/search?q={query}&region={시도명}` | NEIS API 학교 검색 |
| GET | `/schools/academies/search?q={query}&region={}&subject={}` | NEIS API 학원 검색 |

### 게시글 (posts)

| Method | Path | 설명 |
|--------|------|------|
| GET | `/posts?board_type={}&page={}&size={}&q={}` | 게시글 목록 (검색 포함) |
| POST | `/posts` | 게시글 작성 (금칙어 검사 + nickname_type 선택) |
| GET | `/posts/{id}` | 게시글 상세 (조회수 +1) |
| PATCH | `/posts/{id}` | 게시글 수정 (본인만, 금칙어 검사 포함) |
| DELETE | `/posts/{id}` | 게시글 소프트 삭제 (본인만) |
| POST | `/posts/{id}/like` | 좋아요 토글 |
| POST | `/posts/{id}/scrap` | 스크랩 토글 |
| GET | `/posts/me/scraps` | 내 스크랩 목록 |
| GET | `/posts/{id}/comments` | 댓글 목록 (스레드 익명화 레이블 포함) |
| POST | `/posts/{id}/comments` | 댓글 작성 (금칙어 검사 + FCM 발송) |
| DELETE | `/posts/{id}/comments/{cid}` | 댓글 소프트 삭제 (본인만) |
| POST | `/posts/{id}/comments/{cid}/like` | 댓글 좋아요 토글 |
| POST | `/posts/report` | 신고 (카테고리 선택 + 사유 입력) |

### 학원 (academies) — 신규

| Method | Path | 설명 |
|--------|------|------|
| GET | `/academies?region={}&subject={}&school_type={}` | 학원 목록 (필터링) |
| GET | `/academies/{id}` | 학원 상세 (프로필 + 후기 요약) |
| GET | `/academies/{id}/reviews` | 학원 후기 목록 |
| POST | `/academies/{id}/reviews` | 학원 후기 작성 (인증 닉네임 또는 익명 선택) |
| POST | `/academies/{id}/reviews/{rid}/like` | 후기 좋아요 토글 |
| POST | `/academies/report` | 학원 후기 신고 |

### 차단 (users)

| Method | Path | 설명 |
|--------|------|------|
| POST | `/users/{target_id}/block` | 차단 등록 |
| DELETE | `/users/{target_id}/block` | 차단 해제 |
| GET | `/users/blocks` | 내 차단 목록 조회 |

### DM / 실시간 (conversations, stream)

| Method | Path | 설명 |
|--------|------|------|
| GET | `/conversations` | 내 대화 목록 (안 읽은 메시지 수 포함) |
| POST | `/conversations/{other_user_id}` | 대화방 생성 또는 기존 반환 |
| GET | `/conversations/{id}/messages` | 메시지 목록 (읽음 처리 자동) |
| POST | `/conversations/{id}/messages` | 메시지 전송 (SSE 이벤트 + FCM 발송) |
| GET | `/stream` | SSE 실시간 이벤트 스트림 |

---

## 6. 화면 구성 및 UI 레이아웃

### 6-1. 전체 네비게이션 구조

```
앱 진입
  ├── [미인증] → 전화번호 입력 → SMS 인증 → 학교 선택 → 게시판
  └── [인증됨] → 게시판 (바텀 네비)

바텀 네비게이션 (4탭, StatefulShellRoute)
  ├── [게시판] — 인증닉네임 / 익명 / 지역·학교·학년 TabBar
  ├── [학원]   — 학원 검색 + 후기 DB
  ├── [검색]   — 전체 게시판 텍스트 검색
  └── [대화]   — 1:1 DM 목록 (SSE 실시간 연결)

전체 화면 (바텀 네비 위)
  ├── 게시글 상세 (/board/:postId)
  ├── 글쓰기 (/board/write)
  ├── 학원 상세 (/academy/:academyId)
  ├── 학원 후기 작성 (/academy/:academyId/review/write)
  ├── DM 채팅 (/dm/:convId)
  └── 프로필 (/profile)
```

### 6-2. 게시판 화면 (board_screen)

```
AppBar: "MomsTalk"                          [프로필 아이콘]
─────────────────────────────────────────────────────────
TabBar: [인증닉네임] [익명고민] [기장군] [학교] [1학년] [전체]
─────────────────────────────────────────────────────────
게시글 카드:
┌───────────────────────────────────────────────────┐
│ [인증] 행복초_지혜맘  ·  2시간전          [···] │
│                                                   │
│ [추천] 부산과학고 수학 학원 추천 부탁드려요        │
│ @기장군  @1학년  (mention 태그)                   │
│                                                   │
│ ♡ 12    💬 5    👁 128                           │
└───────────────────────────────────────────────────┘
┌───────────────────────────────────────────────────┐
│ 🔵 익명  ·  30분전                          [···] │
│                                                   │
│ 담임 선생님 민원 어떻게 하셨나요                  │
│                                                   │
│ ♡ 3    💬 12    👁 88                            │
└───────────────────────────────────────────────────┘

[글쓰기 FAB]
```

### 6-3. 학원 탭 화면 (academy_screen) — 신규

```
AppBar: "학원 정보"
─────────────────────────────────────────────────────────
[지역 필터] [과목 필터] [학교급 필터]
─────────────────────────────────────────────────────────
학원 카드:
┌───────────────────────────────────────────────────┐
│ 🏫 부산수학학원                  ★4.2 (후기 23건) │
│ 기장군 · 수학 · 중등                              │
│                                                   │
│ 최신 후기: "꼼꼼하게 가르쳐주고 숙제량 적당해요" │
│ 행복초_지혜맘 · 2일전                            │
└───────────────────────────────────────────────────┘

[내 학교 근처 학원 보기]
```

### 6-4. 학원 상세 화면 (academy_detail_screen) — 신규

```
AppBar: "학원 정보"
─────────────────────────────────────────────────────────
부산수학학원
기장군 기장읍 · ☎ 051-000-0000
과목: 수학 / 학교급: 중등

[B2B 공식 프로필: 원장 소개 / 커리큘럼 / 사진]  ← B2B 유료
─────────────────────────────────────────────────────────
후기 요약
  ★ 4.2 / 5.0 (23개)
  선생님 스타일: 꼼꼼형 70% · 엄격형 20% · 자유형 10%
  숙제량: ★★☆ 평균
  성적 향상: 올랐어요 61%

[후기 작성하기]
─────────────────────────────────────────────────────────
후기 목록
  ★★★★☆  행복초_지혜맘  ·  2일전
  꼼꼼형 / 숙제★★☆ / 성적 향상
  "꼼꼼하게 가르쳐줘서 성적이 올랐어요"          [♡ 3]
```

### 6-5. 학원 후기 작성 화면 (academy_review_write_screen) — 신규

```
AppBar: "후기 작성"                              [등록]
─────────────────────────────────────────────────────────
학원명: 부산수학학원 (자동 입력)

과목 선택:  [수학▼]

선생님 스타일:
  ◯ 꼼꼼형   ◯ 자유형   ◯ 엄격형

숙제량:
  ◯ ★☆☆ 적음   ◯ ★★☆ 보통   ◯ ★★★ 많음

성적 향상도:
  ◯ 많이 올랐어요  ◯ 조금 올랐어요  ◯ 그대로에요  ◯ 내렸어요

별점: ★★★★☆

한마디 (100자):
┌────────────────────────────────────────────────┐
│ 꼼꼼하게 가르쳐줘서 좋았어요                   │
└────────────────────────────────────────────────┘

공개 방식:
  ◉ 인증 닉네임 (행복초_지혜맘) — 신뢰도 높음
  ◯ 완전 익명
```

### 6-6. 글쓰기 화면 (post_write_screen)

```
AppBar: "글쓰기"                                [등록]
─────────────────────────────────────────────────────────
게시판 선택: [인증닉네임 ▼]  ← 학원/입시 게시판
            [익명 고민 ▼]   ← 민감 내용

제목 입력
────────────────
본문 입력 (Expanded)

[전체 게시판일 때만]
@태그: [@기장군] [@부산중앙고등학교] [@1학년]

────────────────
공개 방식:
  ◉ 인증 닉네임 (행복초_지혜맘)   ← 인증닉네임 게시판 기본값
  ◯ 완전 익명                      ← 익명 게시판 기본값
```

### 6-7. 신고 카테고리 다이얼로그 (공통 컴포넌트)

```
┌─────────────────────────────────────┐
│ 신고하기                            │
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
│              [취소]  [신고]          │
└─────────────────────────────────────┘
```

> **학원 후기 신고 추가 항목**: `FAKE_REVIEW` (허위/광고성 후기), `COMPETITOR` (경쟁 학원 비방)

### 6-8. 검색 화면 (search_screen)

```
AppBar: [🔍 게시글·학원 검색__________] [✕]
─────────────────────────────────────────────────────────
[게시글] [학원]  ← 탭 전환
결과 목록
```

### 6-9. DM 화면 (dm_list_screen + dm_chat_screen)

기존과 동일. SSE 실시간 연결 유지.

### 6-10. 프로필 화면 (profile_screen)

- 인증 닉네임 + 익명 닉네임 표시
- 지역, 학교명, 학년
- 매너온도
- 내 게시글 / 내 학원 후기 / 스크랩 목록
- 로그아웃 / 회원 탈퇴

---

## 7. 게시판 구조 — 선택적 실명제

### 7-1. 게시판 유형 (board_type)

| board_type | 탭 표시명 | 닉네임 정책 | 접근 범위 |
|-----------|----------|------------|----------|
| `certified` | 인증닉네임 | 인증 닉네임 고정 표시 | 학원 추천·입시 정보 중심 |
| `anonymous` | 익명 고민 | 완전 익명 (선택 시) | 교사 민원·교우 관계 등 민감 주제 |
| `region` | 지역명 (예: 기장군) | 닉네임 유형 선택 가능 | 동일 `region` 유저들의 글 |
| `school` | 학교명 | 닉네임 유형 선택 가능 | 동일 `school_code` 유저들의 글 |
| `grade` | N학년 | 닉네임 유형 선택 가능 | 동일 학교 + 동일 학년 |
| `free` | 전체 | 닉네임 유형 선택 가능 | 모든 글 |

### 7-2. 선택적 실명제 운영 원칙

| 게시판 | 작동 방식 |
|--------|----------|
| **인증 닉네임 게시판** | `certified_nickname` 자동 표시. 익명 선택 불가. 학원 후기·입시 전략 등 신뢰도 필요 콘텐츠. 책임감 기반으로 허위 후기·비방 자연 억제. |
| **완전 익명 게시판** | `is_anonymous=true` 시 닉네임 미표시. Auth DB ↔ Service DB 물리 분리로 역추적 불가. 교사 민원·가정사 등 껄끄러운 주제 전용. |
| **일반 게시판** | 작성 시 '인증 닉네임 / 완전 익명' 중 선택. |

### 7-3. 학원 후기 신뢰도 레이블

| 조건 | 표시 |
|------|------|
| 인증 닉네임으로 작성 | [인증] 배지 + 학교 약칭 노출 |
| 익명으로 작성 | 🔵 익명 표시 |

### 7-4. @태그 (mention_tags) 시스템

- `free` 게시판 글 작성 시 `@기장군`, `@부산중앙고등학교`, `@1학년` 등 태그 선택
- 저장 형식: `["region:기장군", "school:B100000011", "grade:1"]`
- 조회 시 현재 유저의 프로필과 매칭되는 태그가 있는 글을 **상단** 정렬
- 앱에서 매칭된 게시글에 **[추천]** 배지 표시

---

## 8. 학원 후기 시스템

### 8-1. 핵심 전략 — Cold Start 방어

NEIS 학원 API로 전국 학원 목록을 **선구축**하여 빈 플랫폼 인상 차단.  
유저는 5항목 정형 템플릿으로 후기만 작성 → 진입 허들 최소화.

### 8-2. 후기 작성 템플릿

| 항목 | 입력 방식 | 옵션 |
|------|----------|------|
| 학원명 | NEIS 연동 자동완성 선택 | |
| 과목 | 드롭다운 선택 | 수학 / 영어 / 과학 / 국어 / 기타 |
| 선생님 스타일 | 3단 라디오 선택 | 꼼꼼형 / 자유형 / 엄격형 |
| 숙제량 | 별점 선택 | ★☆☆ / ★★☆ / ★★★ |
| 성적 향상도 | 4단 선택 | 많이 올랐어요 / 조금 올랐어요 / 그대로에요 / 내렸어요 |
| 총평 | 100자 이내 자유 입력 | |
| 공개 방식 | 라디오 선택 | 인증 닉네임 / 완전 익명 |

### 8-3. 학원 랭킹 지표

| 지표 | 계산 방식 |
|------|----------|
| 평균 별점 | 후기 별점 단순 평균 |
| 성적 향상률 | "많이+조금 올랐어요" 비율 |
| 인기도 | 조회수 + 좋아요 + 후기 수 가중합 |
| 지역 랭킹 | 지역×과목 기준 필터링 후 인기도 순 |

> **Phase 3 (Month 13~) 유료 기능**: 최근 3개월 랭킹 조회, 타 지역 학원 정보 열람 → B2C 프리미엄 구독

### 8-4. 학원 이의 신청 (명예훼손 대응)

- 학원 상세 화면에 "이 후기에 이의 제기" 버튼 제공
- 후기 작성 시 자동 면책 문구 삽입: "이 후기는 작성자 개인 경험을 바탕으로 한 의견입니다."
- 이의 신청 접수 → 관리자 24시간 내 검토 → 삭제 또는 유지 처리
- 운영 정책 페이지에 학원 후기 작성 가이드라인 공지

---

## 9. 신고 시스템

### 9-1. 현재 구현 상태

- 신고 대상: 게시글(post) / 댓글(comment) / 학원후기(academy_review)
- 동일 유저의 동일 대상 중복 신고 차단 (DB UNIQUE 제약)
- 8가지 카테고리 선택 + 기타 사유 직접 입력
- 누적 5건 → `is_hidden = True` 자동 블라인드
- Streamlit 관리자 대시보드에서 검토·처리

### 9-2. 신고 카테고리

| 코드 | 표시명 |
|------|--------|
| `SPAM` | 스팸/홍보 |
| `OBSCENE` | 음란/선정적 내용 |
| `ABUSE` | 욕설/비방/혐오 |
| `PERSONAL_INFO` | 개인정보 노출 |
| `MISINFORMATION` | 허위 사실/명예훼손 |
| `ILLEGAL` | 불법 정보 |
| `OFF_TOPIC` | 주제와 무관한 게시물 |
| `FAKE_REVIEW` | 허위/광고성 후기 (학원 후기 전용) |
| `OTHER` | 기타 (직접 입력 필수) |

### 9-3. 신고 처리 절차

```
신고 접수 → report_count 증가
    │
    ├─ 1~4건: 기록만
    ├─ 5건:   is_hidden = True (자동 블라인드) + 작성자 FCM 알림
    └─ 10건:  긴급 플래그 → Streamlit 대시보드 상단 노출

관리자 검토 (Streamlit 대시보드)
    │
    ├─ [정상 판단] → is_hidden = False 복원
    │               허위 신고자 경고 1회
    └─ [위반 판단] → 게시글/댓글 영구 삭제
                     작성자 조치 (user_warnings 기록)
                     경고 1회 → 경고 2회: 7일 정지 → 3회: 30일 정지
                     5회 or 중대 위반: 영구 정지
```

---

## 10. 차단 및 숨기기

### 현재 구현

- `POST /users/{target_id}/block` — 차단 등록
- `DELETE /users/{target_id}/block` — 차단 해제
- `GET /users/blocks` — 차단 목록 조회 (신규 구현 예정)
- 게시글 목록 조회 시 차단된 유저의 게시글 자동 필터링

### 보완 필요

| 항목 | 설명 |
|------|------|
| 댓글 차단 필터링 | 현재 게시글만 필터, 댓글은 미적용 |
| DM 차단 연동 | 차단된 유저에게 DM 발신 불가 처리 |

---

## 11. 1:1 대화 (DM)

### 현재 구현

- 게시글/댓글 더보기 → "대화하기" → 대화방 자동 생성(또는 기존 반환)
- 메시지 목록 조회 시 자동 읽음 처리
- 대화 목록: 마지막 메시지 미리보기 + 안 읽은 메시지 수 배지
- SSE 실시간 수신, FCM 푸시

### 보완 필요

| 항목 | 설명 |
|------|------|
| 차단 연동 | 차단된 유저에게 DM 발신 차단 |
| 채팅방 내 SSE | 목록만 실시간, 채팅방 내부는 전송 후 자동 갱신 방식 |

---

## 12. 계정 정지 시스템

**계정 상태 판단 순서 (`get_current_user` 의존성 주입 단계에서 순차 검증):**

```
1. JWT 유효성 검사 → 실패 시 401
2. 유저 존재 여부 → 없으면 401
3. is_banned == True → 403 "영구 정지된 계정입니다."
4. suspended_until > now → 403 "계정이 정지되었습니다. 해제 시각: {datetime}"
   (응답 헤더 X-Suspend-Until: ISO 8601 시각 포함)
5. 정상 → 유저 객체 반환
```

| 유형 | 컬럼 | 해제 방법 |
|------|------|----------|
| 기간 정지 | `suspended_until` (DateTime) | 해제 시각 경과 시 자동 해제 |
| 영구 정지 | `is_banned` (Boolean) | 관리자 수동 해제만 가능 |

---

## 13. 스레드 익명화

### 레이블 규칙

| 조건 | 표시 레이블 |
|------|------------|
| 익명 댓글 + 게시글 작성자 본인 | "글쓴이" |
| 익명 댓글 + 최초 등장 타인 | "익명1" |
| 익명 댓글 + 두 번째 등장 타인 | "익명2" |
| 인증 닉네임 댓글 | `certified_nickname` 표시 |
| 비익명 댓글 (일반) | `anon_nickname` 표시 |
| 본인이 작성한 댓글 | `is_mine: true` → "나" 뱃지 추가 |

서버 런타임 계산 — DB에 저장하지 않음 (상태 변화에 강건).

---

## 14. 금칙어 필터링

### 구현 위치

`backend/app/core/profanity.py`

### 동작 방식

게시글/댓글 **작성 및 수정** 시 서버에서 금칙어 검사 → 포함 시 400 Bad Request

### 적용 범위

| 위치 | 검사 대상 | 상태 |
|------|----------|------|
| `post_service.create_post` | 제목 + 본문 | ✅ 구현 |
| `comment_service.create_comment` | 댓글 내용 | ✅ 구현 |
| `post_service.update_post` | 제목 + 본문 | ⬜ 구현 필요 |
| `academy_review_service.create_review` | 총평 | ⬜ 구현 필요 |

### 금칙어 관리

| 방법 | 설명 |
|------|------|
| 기본 목록 | 코드 내 하드코딩 |
| 운영자 추가 | `PROFANITY_WORDS` 환경변수 |
| Streamlit UI | 관리자 대시보드에서 실시간 추가/삭제 (구현 예정) |

---

## 15. 푸시 알림 (FCM)

### 알림 발송 시점

| 이벤트 | 수신자 | 알림 내용 |
|--------|--------|----------|
| 내 게시글에 댓글 | 게시글 작성자 | "새 댓글이 달렸어요: {댓글 내용 50자}" |
| DM 수신 | DM 수신자 | "{닉네임}님의 메시지: {내용 80자}" |

**알림 payload:**
```json
{"type": "comment", "post_id": "123"}
{"type": "dm", "conversation_id": "456"}
```

### 활성화 방법

1. Firebase Console → 서비스 계정 → "새 비공개 키 생성"
2. 다운로드 JSON을 `.env`에: `FCM_SERVICE_ACCOUNT_JSON={...}`
3. `pubspec.yaml`에 `firebase_messaging` 패키지 추가 (현재 미추가)

---

## 16. 실시간 DM (SSE)

**서버 (`backend/app/core/sse_manager.py`):**
- `user_id → set[asyncio.Queue]` 인메모리 딕셔너리
- 25초 heartbeat
- **주의**: 단일 인스턴스 전용. 멀티 인스턴스 배포 시 Redis Pub/Sub으로 교체 필요

**DM 발송 플로우:**
```
POST /conversations/{id}/messages
    ↓
DirectMessage DB 저장
    ↓
sse_manager.publish(recipient_id, "new_message", {...})  ← SSE (포그라운드)
    ↓
send_push(recipient.fcm_token, ...)                       ← FCM (백그라운드/종료)
```

---

## 17. 보안 설계

### 17-1. 현재 구현된 보안 항목

| 항목 | 상태 |
|------|------|
| 전화번호 비저장 | ✅ |
| HMAC 익명화 | ✅ |
| JWT Bearer 인증 | ✅ |
| Access Token 60분 만료 | ✅ |
| Refresh Token 30일 만료 | ✅ |
| 자동 토큰 갱신 (Dio 인터셉터) | ✅ |
| CORS 화이트리스트 | ✅ |
| 본인 게시글만 수정/삭제 검증 | ✅ |
| 중복 신고/좋아요 차단 (DB UNIQUE) | ✅ |
| SMS 인증코드 5분 TTL | ✅ |
| Soft Delete | ✅ |
| 영구/기간 정지 차단 (403) | ✅ |
| 서버 금칙어 필터 (작성 시) | ✅ |
| Rate Limiting (Redis) | ✅ |
| 약관·개인정보처리방침 페이지 | ✅ |

### 17-2. 보완 필요 보안 항목

| 항목 | 우선순위 | 설명 |
|------|----------|------|
| HTTPS 강제 | 🔴 높음 | Nginx + Let's Encrypt |
| 토큰 블랙리스트 | 🟡 중간 | 로그아웃 시 Refresh Token 무효화 (Redis 필요) |
| 학교 인증 재검증 | 🟡 중간 | 졸업/전학 시 연 1회 NEIS 재인증 강제 |
| 게시글 수정 금칙어 | 🟡 중간 | 수정 시 미적용 |
| 학원 후기 허위 광고 탐지 | 🟡 중간 | IP 기반 동일 학원 집중 후기 패턴 탐지 |

### 17-3. 프로덕션 체크리스트

```
□ SECRET_KEY: 64자 이상 랜덤 문자열
□ ANON_HASH_SECRET: SECRET_KEY와 완전히 다른 값
□ DEBUG=false
□ ALLOWED_ORIGINS: 실제 도메인만
□ FCM_SERVICE_ACCOUNT_JSON 설정
□ PostgreSQL 비밀번호 강화
□ Redis AUTH 설정
□ DB 백업 (RDS 자동 스냅샷 일 1회)
□ HTTPS 인증서 (Nginx + Let's Encrypt)
□ SSE 멀티 인스턴스 배포 시 Redis Pub/Sub 전환
```

---

## 18. 관리자 시스템 — Streamlit 대시보드

**방향**: FastAPI 별도 관리자 API 대신 **Streamlit 기반 내부 도구**로 구축.  
1인 운영 최적화, 개발 속도 우선.

### 18-1. 대시보드 기능 목록

| 메뉴 | 기능 |
|------|------|
| 홈 | 오늘/주간 신고 건수, 가입자 추이, MAU 현황 |
| 신고 처리 | pending 신고 목록 → 원문 확인 → 기각/경고/정지/삭제 처리 |
| 유저 관리 | 유저 검색, 경고 이력, 기간 정지, 영구 정지, 정지 해제 |
| 게시글 관리 | 블라인드 처리, 블라인드 해제, 강제 삭제 |
| 학원 후기 관리 | 허위 후기 신고 처리, 이의 신청 검토 |
| 금칙어 관리 | 금칙어 목록 조회·추가·삭제 (DB 반영) |
| 지역 매니저 | 매니저별 월간 활동 현황, 리워드 정산 |
| B2B 학원 | B2B 신청 목록, 구독 활성화/만료 관리 |

### 18-2. 기술 스택

| 항목 | 내용 |
|------|------|
| 프레임워크 | Streamlit (Python) |
| DB 접근 | Service DB 직접 접근 (내부 네트워크 전용) |
| 인증 | Streamlit secrets + IP 화이트리스트 (내부망 전용) |
| 배포 | Docker Compose 별도 서비스 (외부 미노출) |

### 18-3. 관리자 처리 로그 (감사 추적)

```sql
admin_actions:
  id            INT PK
  admin_email   VARCHAR(100)
  action_type   VARCHAR(30)   -- hide_post / delete_post / warn_user / suspend / ban / unban / dismiss_report / approve_b2b
  target_type   VARCHAR(20)
  target_id     INT
  note          TEXT
  created_at    DATETIME
```

---

## 19. 수익화 모델

### 19-1. 3트랙 수익 모델

| 트랙 | 개시 시점 | 내용 | 목표 매출 (Year 2) |
|------|----------|------|-------------------|
| **BM1 학원 B2B 프로필** | Month 12 | 동네 학원·교습소 원장에게 공식 프로필 개설 권한. 월 3~10만원 (규모별 차등) | 등록 학원 100곳 × 월 5만원 = 월 500만원 |
| **BM2 타겟 네이티브 광고** | Month 18 | 지역+자녀 학년 100% 검증된 초고관여 타겟. 게시글 형태 스폰서드 콘텐츠 | MAU 1만 × CPM 5,000원 = 월 100~200만원 |
| **BM3 B2C 프리미엄 구독** | Month 24 | 최근 3개월 학원 랭킹, 타 지역 열람, 입시 Q&A. 월 3,900원 | MAU 5만 × 5% = 2,500명 × 3,900원 = 월 975만원 |

### 19-2. B2B 프로필 상세

| 기능 | 무료 | B2B 유료 |
|------|------|---------|
| 기본 학원 정보 (NEIS 연동) | ✅ | ✅ |
| 후기 노출 | ✅ | ✅ |
| 원장 소개 등록 | ❌ | ✅ |
| 커리큘럼·사진 등록 | ❌ | ✅ |
| 지역 검색 상단 노출 | ❌ | ✅ |
| 이의 신청 우선 처리 | ❌ | ✅ |

### 19-3. 운영 비용 (출시 초기 월 기준)

| 항목 | 금액 |
|------|------|
| AWS 서버 (t3.medium × 2) | 25~40만원 |
| SMS 인증 (NHN/카카오) | 5~10만원 |
| 지역 매니저 리워드 (20명) | 30~50만원 |
| 도메인 + SSL | 2,500원 |
| Firebase FCM | 무료 |
| NEIS API | 무료 |
| **합계** | **약 60~100만원/월** |

---

## 20. 로드맵 및 KPI

### 20-1. Phase별 마일스톤

| Phase | 기간 | 핵심 목표 | KPI |
|-------|------|----------|-----|
| **Phase 1** | Month 1~6 | PWA 출시 + 부산 집중 시드 콘텐츠 | 가입자 1,000명 / MAU 500명 / 학원 후기 1,000건 / D30 리텐션 20% |
| **Phase 2** | Month 7~12 | 전국 오픈 + MAU 성장 | MAU 3,000명 / 학원 후기 5,000건 / iOS 앱 출시 / B2B 파이프라인 20곳 |
| **Phase 3** | Month 13~18 | iOS 앱 출시 + 수익화 시작 | MAU 5,000명 / B2B 유료 50곳 / 월 매출 200만원 / DAU/MAU 25% |
| **Phase 4** | Month 19~36 | Android 출시 + 스케일업 | MAU 5만명 (Month 36) / 월 매출 1,500만원 / 흑자 전환 |

### 20-2. Cold Start 전략

- **런칭 전**: 부산 교육 특구(해운대·동래·연제구) 학부모 지역 매니저 20~30명 선발
- **활동 조건**: 첫 달 학원 후기 20건 + 주 3회 게시판 활동 (리워드 월 1.5~2.5만원)
- **D-Day 목표**: 학원 후기 500건, 게시글 200건 확보 후 공개
- **채널**: 카카오톡 오픈채팅 학부모 그룹 베타 테스터 모집

### 20-3. 핵심 KPI

| KPI | 목표 | 근거 |
|-----|------|------|
| D30 리텐션 | 20% 이상 | 학원 정보는 분기별 필요 발생 → 월 1회 이상 방문 유도 |
| 세션 길이 | 평균 5분 이상 | 학원 후기 3~4개 읽기 = 약 4~6분 |
| B2B 전환율 | 무료 등록 학원의 10~15% | 유사 로컬 B2B SaaS 벤치마크 |
| 구독 전환율 | MAU 대비 5% | 교육 관여도 높은 타겟 특성 |

---

## 21. 미구현 / 보완 필요 항목

### 출시 전 필수 (P0) 🔴

| 항목 | 설명 |
|------|------|
| Streamlit 관리자 대시보드 | 신고처리·경고·금칙어 관리 최소 기능 구현 |
| 게시글 수정 금칙어 검사 | 수정 시 미적용 |
| 댓글 차단 필터링 | 게시글만 필터, 댓글 미적용 |
| 차단 목록 조회 API | `GET /users/blocks` 미구현 |
| 차단 DM 연동 | 차단된 유저에게 DM 발신 가능 (미차단) |
| 개인정보처리방침 · 이용약관 페이지 | 출시 전 법률 자문 후 게시 필수 |
| 학원 이의 신청 UI | 허위 후기 대응 — 명예훼손 리스크 관리 |
| 인증 닉네임 시스템 | `certified_nickname` 컬럼 추가 및 게시판 분리 구현 |

### 핵심 기능 (P1) 🟡

| 항목 | 설명 |
|------|------|
| 학원 후기 시스템 | `academies`, `academy_reviews` 테이블 + API + UI 전체 |
| NEIS 학원 API 연동 | 학원 목록 선구축 (시드 콘텐츠 전략 핵심) |
| Firebase 앱 설정 | `firebase_messaging` 패키지 추가, 실제 FCM 활성화 |
| 채팅방 내 SSE | 채팅방 내부도 실시간으로 전환 |
| 알림 탭 | 댓글/신고/정지 인앱 알림 목록 |
| 토큰 블랙리스트 | 로그아웃 시 Refresh Token 무효화 (Redis 필요) |
| 게시판 정렬 옵션 | 최신순만 있음 → 인기순 추가 |
| 무한 스크롤 | 현재 고정 20개 반환 |

### 스케일업 (P2) 🔵

| 항목 | 설명 |
|------|------|
| iOS 네이티브 앱 | MAU 5,000 달성 후 개발 |
| Android 앱 | Phase 4 |
| B2B 학원 프로필 구독 | Month 12 수익화 |
| 프리미엄 구독 (B2C) | Month 24 수익화 |
| SSE → Redis Pub/Sub | 멀티 인스턴스 배포 시 전환 |
| 매너온도 변동 로직 | 컬럼만 존재, 로직 없음 |
| 이미지 첨부 | S3 presigned URL 방식 |
| 다크 모드 | 미지원 |

---

## 22. 인프라 및 배포

### 22-1. 현재 Docker Compose 구성 (로컬 개발)

| 서비스 | 이미지 | 포트 | 역할 |
|--------|--------|------|------|
| `momstalk_backend` | Python 3.12 | 8000 | FastAPI 앱 |
| `momstalk_db` | PostgreSQL | 5432 | **통합 단일 DB** (인증+서비스 전체) |
| `momstalk_redis` | Redis | 6379 | Rate Limit + 향후 토큰 블랙리스트 |
| `momstalk_admin` | Streamlit | 8501 | 관리자 대시보드 |

### 22-2. 배포 조합 (웹앱 MVP)

| 역할 | 서비스 | 비용 |
|------|--------|------|
| **프론트엔드 (Flutter Web)** | GitHub Pages | 무료 |
| **백엔드 (FastAPI)** | Render Web Service | 무료~$7/월 |
| **DB (PostgreSQL)** | Supabase (프로젝트 1개) | 무료 500MB |
| **Redis** | Upstash | 무료 (1만 req/일) |
| **관리자 (Streamlit)** | Render Web Service | 무료 |

### 22-3. 환경변수 (.env)

```ini
# DB (Supabase 배포 시 Supabase connection string으로 교체)
DATABASE_URL=postgresql+asyncpg://...@db:5432/momstalk_db
REDIS_URL=redis://localhost:6379/0

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
ALLOWED_ORIGINS=http://localhost:3000,https://momstalk.kr
```

### 22-4. 향후 프로덕션 인프라 (스케일업 시)

```
사용자 PWA (GitHub Pages / CDN)
    │ HTTPS
FastAPI (Render / 자체 서버)
    │
Supabase PostgreSQL (단일 DB)
Upstash Redis
```

> **SSE + Render**: `/api/v1/stream` 엔드포인트는 Render에서 SSE 지원됨. 단, 무료 티어는 30초 타임아웃이 있으므로 유료($7) 플랜 필요.

---

*이 문서는 2026-06-27 기준 구현 상태와 사업계획서 v1.0 (2026년 7월)을 통합 반영합니다.*



GET /users/blocks API 추가 + Streamlit 금칙어 관리 페이지

DB Migration 0007: profanity_words + certified_nickname + nickname_type 콼럼 추가

백엔드: certified_nickname 자동 생성 + nickname_type 지원 (모델/서비스/스키마)

프론트: 글쓰기 화면 닉네임 유형 선택 UI + 게시판 탭 인증닉네임/익명 구분

법률 페이지 확인 및 라우터 등록 (약관/개인정보처리방침)

DB Migration 0008: academies, academy_reviews 테이블 추가

백엔드: 학원 후기 시스템 + NEIS 학원 API 연동 (acaInsTiInfo)

프론트: 학원 탭 + 학원 상세 + 후기 작성 화면 + 바텀 네비 4탭

게시판 인기순 정렬 + 무한 스크롤 (cursor 기반 페이지네이션)

FCM 실제 활성화 (pubspec.yaml firebase_messaging 추가)