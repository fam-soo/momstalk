# MomsTalk (맘스톡크) — 제품 사양서 및 개발 현황 문서

> 작성 기준일: 2026-07-06  
> 현재 버전: v0.6.1  
> 플랫폼: Flutter Web PWA (출시, Android/iOS는 홈 화면 추가 설치 방식으로 병행 가능) → 네이티브 앱 스토어는 MAU 안정화 후  
> 백엔드: FastAPI + PostgreSQL (Supabase 단일 DB)  
> 배포: Vercel (Flutter Web) + Render (FastAPI) + Supabase (PostgreSQL)  
> 실사용자 온보딩 시작 — 23장에 활성화·개선 방안 정리

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
18. [관리자 시스템 — Flutter 인앱 + Streamlit](#18-관리자-시스템--flutter-인앱--streamlit)
19. [수익화 모델](#19-수익화-모델)
20. [로드맵 및 KPI](#20-로드맵-및-kpi)
21. [미구현 / 보완 필요 항목](#21-미구현--보완-필요-항목)
22. [인프라 및 배포](#22-인프라-및-배포)
23. [활성화 및 시스템 개선 방안](#23-활성화-및-시스템-개선-방안)

---

## 1. 서비스 개요

**MomsTalk(맘스톡크)**는 카카오 계정 + 알림장 캡처 인증 기반의 학부모 전용 교육 정보 커뮤니티 플랫폼이다.  
초대 링크(QR 코드) 기반 가입, 학원 정보 구조화, 선택적 실명제를 결합하여 신뢰할 수 있는 **하이퍼로컬 교육 정보 허브**를 구축한다.

### 핵심 원칙

| 원칙 | 설명 |
|------|------|
| **초대 기반 가입** | 학교 담당자(관리자)가 발급한 QR 코드 초대 링크로만 가입 → 재학 학부모 신뢰도 보장 |
| **알림장 캡처 인증** | 가입 후 학교 알림장/가정통신문 사진 업로드 → 관리자 심사 → 정회원 승급 |
| **선택적 실명제** | 학원 후기·입시 정보는 인증 닉네임, 민감 고민은 완전 익명 분리 운영 |
| **다자녀 지원** | 한 계정에 여러 자녀/학교 등록, 활성 자녀 전환 기능 |
| **구조화 학원 DB** | NEIS 학원 목록 선구축 + 5항목 정형 리뷰 템플릿 → Cold Start 방어 |
| **자동 중재** | 신고 5건 누적 자동 블라인드, Flutter 인앱 + Streamlit 관리자 도구로 1인 운영 최적화 |
| **스레드 익명화** | 같은 게시글 내 댓글 "글쓴이/익명1/익명2…" 레이블로 익명성 유지 |

### 포지셔닝

| 플랫폼 | 한계 | MomsTalk 차별점 |
|--------|------|----------------|
| 네이버 맘카페 | 텃세·여론통제·광고 후기 난무 | 인증 기반 + 선택적 실명제로 신뢰 확보 |
| 밴드(카카오) | 폐쇄 그룹, 공개 학원 DB 없음 | 지역×학교급×과목 구조화 리뷰 |
| 클래스팅 | B2B 중심, 학부모 커뮤니티 기능 없음 | 양방향 커뮤니티 + 학원 후기 |

---

## 2. 아키텍처 설계

```
┌──────────────────────────────────────────────────────────┐
│  Flutter Web PWA (Vercel 배포)                            │
│  ┌──────────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐  │
│  │ 게시판 탭    │ │ 학원 탭  │ │ 검색 탭  │ │대화 탭 │  │
│  └──────────────┘ └──────────┘ └──────────┘ └────────┘  │
│  Dio + JWT Bearer + SharedPreferences (Web)               │
└─────────────────────┬────────────────────────────────────┘
                      │ HTTPS / REST / SSE
┌─────────────────────▼────────────────────────────────────┐
│  FastAPI (Python 3.12, Uvicorn) — Render 배포            │
│  Port 8000                                               │
│                                                          │
│  /api/v1/auth/*         인증 + 캡처 업로드 + 초대 링크   │
│  /api/v1/schools/*      NEIS 학교·학원 검색              │
│  /api/v1/posts/*        게시글/댓글/신고                 │
│  /api/v1/academies/*    학원 프로필 + 후기               │
│  /api/v1/users/*        차단 (Block)                     │
│  /api/v1/conversations/* 1:1 DM                         │
│  /api/v1/admin/*        관리자 API (Flutter 인앱 전용)   │
│  /api/v1/stream         SSE 실시간 이벤트 스트림         │
│                                                          │
│  start.sh: alembic upgrade head → uvicorn 시작           │
└──────────────────────┬───────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────┐
│  Supabase PostgreSQL (단일 통합 DB)                      │
│  - 인증 / 사용자 / 게시글 / 댓글 / 학원 후기             │
│  - 신고 / 차단 / DM / 관리자 로그                        │
│  - 알림장 캡처 이미지 원본(BYTEA) — 심사 후 즉시 삭제    │
└──────────────────────────────────────────────────────────┘
```

> 알림장 캡처 이미지는 별도 오브젝트 스토리지(Supabase Storage) 없이 `auth_captures.image_data`(BYTEA)에 직접 저장한다. 이미지가 작고(리사이즈된 사진) 심사 직후 삭제되는 단명 데이터라는 특성상 스토리지 왕복을 없애는 쪽이 더 단순하고 안정적이다 (과거 Supabase Storage 왕복이 반복 업로드 오류의 원인 중 하나였음).

### 기술 스택

| 영역 | 기술 |
|------|------|
| 백엔드 프레임워크 | FastAPI 0.x + Python 3.12 |
| ORM | SQLAlchemy 2.x (async) |
| DB 마이그레이션 | Alembic (Render 배포 시 start.sh에서 자동 실행) |
| 인증 | JWT (HS256) — Access 60분 / Refresh 30일 |
| 소셜 로그인 | 카카오 OAuth (카카오 액세스 토큰 → 서버 JWT 교환) |
| 파일 저장 | Postgres BYTEA (알림장 캡처 이미지, 심사 후 즉시 삭제) |
| 실시간 통신 | SSE (Server-Sent Events) — asyncio Queue 기반 |
| 모바일 프레임워크 | Flutter 3.x |
| 상태 관리 | Riverpod 2.x |
| 라우팅 | go_router 14.x (StatefulShellRoute — 지역/학교/학원/대화/내정보 5탭) |
| HTTP 클라이언트 | Dio 5.x (자동 토큰 갱신 인터셉터, 일반 API) + package:http (캡처 업로드 전용 — 웹 멀티파트 안정성) |
| 이미지 업로드 검증 | 서버가 클라이언트 Content-Type을 신뢰하지 않고 매직바이트로 직접 판별 (`core/image_sniff.py`) |
| 화면 간 상태 동기화 | Riverpod `boardRefreshSignal` 신호 버스 (`core/refresh_bus.dart`) — IndexedStack 탭 간 새로고침/활성 자녀 연동 |
| 관리자 도구 | Flutter 인앱 관리자 화면 + Streamlit (보조) |

---

## 3. 인증 및 계정 설계

### 3-1. 카카오 OAuth 인증 플로우

```
초대 링크(QR 코드) 스캔 → invite_join_screen
        ↓
카카오 로그인 (kakao_flutter_sdk_user)
        ↓
POST /auth/kakao { kakao_access_token }
  └─ 카카오 프로필 조회 → 닉네임 / kakao_id 저장
  └─ 신규: users 레코드 생성 (member_grade: 'lurker')
  └─ 기존: users 레코드 반환
        ↓
JWT Access Token + Refresh Token 발급
        ↓
POST /auth/invite/use { token, grade, class_num }
  └─ user_children에 자녀 등록
  └─ 기존 비회원 → member_grade: 'auth_pending'
  └─ 기존 정회원 → 자녀 학교 추가만
        ↓
알림장 캡처 업로드 화면 (capture_upload_screen)
  └─ POST /auth/capture/upload (package:http 멀티파트) → 이미지를 auth_captures.image_data(BYTEA)에 직접 저장
        ↓
관리자 심사 (Flutter 인앱 관리자 화면, DB에서 바로 조회)
  └─ is_trusted 사용자: 즉시 자동 승인 (image_data 즉시 삭제)
  └─ 일반: 수동 승인/거부
        ↓
승인 → member_grade: 'member' → 정회원 기능 전체 해금

※ 자녀 추가(child_add) 플로우는 is_trusted 사용자에 한해 사진 업로드 화면 자체를
   건너뛰고 POST /auth/me/children으로 즉시 등록한다 (일반 사용자는 캡처 인증 필요).
```

### 3-2. 계정 상태 (member_grade)

| 상태 | 설명 | 접근 가능 기능 |
|------|------|--------------|
| `lurker` | 카카오 로그인만 완료 | school/grade 게시판 읽기 |
| `auth_pending` | 인증 심사 중 | school/grade 읽기 (학교 게시판 접근 제한) |
| `member` | 정회원 | 전체 기능 |
| `admin` | 관리자 | 전체 기능 + 관리자 도구 |

### 3-3. 계정 필드 (users 테이블 현재 상태)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | |
| `anon_id` | String(64) UNIQUE | 고유 식별자 (카카오 기반) |
| `kakao_id` | String(30) | 카카오 계정 ID (관리자 식별용) |
| `anon_nickname` | String(30) | 익명 닉네임 (카카오 닉네임 기반 자동 생성) |
| `certified_nickname` | String(50) | 인증 닉네임 |
| `region` | String(30) | 지역 |
| `school_code` | String(20) | 대표 학교 코드 (deprecated, active_child 사용 권장) |
| `school_name` | String(100) | 대표 학교명 |
| `grade` | Integer | 대표 학년 |
| `class_num` | Integer | 반 (nullable) |
| `school_type` | String(10) | elementary / middle / high |
| `member_grade` | String(20) | lurker / auth_pending / member / admin |
| `manner_score` | Integer | 매너온도 (초기값 100) |
| `fcm_token` | String(256) | Firebase 푸시 토큰 |
| `is_banned` | Boolean | 영구 정지 여부 |
| `suspended_until` | DateTime | 기간 정지 해제 시각 |
| `warning_count` | Integer | 누적 경고 횟수 |
| `active_child_id` | Integer FK | 현재 활성 자녀 ID (user_children 참조) |
| `is_trusted` | Boolean | true 시 캡처 인증 자동 승인 |
| `admin_username` | String | 관리자 계정용 |
| `admin_password_hash` | String | 관리자 비밀번호 해시 |
| `profile_updated_at` | DateTime | 프로필 최종 수정일 |
| `created_at` | DateTime | |

### 3-4. 다자녀 지원 (user_children 테이블)

한 계정에 여러 자녀/학교를 등록할 수 있다. `users.active_child_id`로 현재 활성 자녀를 지정하며, 게시판 필터링은 active child 기준으로 동작한다.

`users.region/school_name/grade/school_type`은 다자녀 지원 이전의 레거시 필드로 "첫 자녀 등록 시"에만 동기화된다. 이 값을 그대로 노출하면 활성 자녀를 바꿔도 지역/학원 탭 등이 예전 자녀 기준으로 보이는 문제가 있어, `/auth/me`를 비롯해 프로필을 반환하는 모든 엔드포인트(닉네임 변경, 학교 변경, 활성 자녀 전환)는 `active_child_id`가 있으면 그 자녀 기준 값으로 덮어써서 응답한다 (`_user_profile_with_active_child`). 학교 변경(`PATCH /auth/me/profile`)도 활성 자녀가 있으면 해당 `UserChild` 레코드를 함께 갱신한다.

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | |
| `user_id` | FK → users | |
| `school_code` | String(20) | |
| `school_name` | String(100) | |
| `grade` | Integer | |
| `class_num` | Integer | nullable |
| `school_type` | String(10) | |
| `region` | String(50) | |
| `created_at` | DateTime | |

---

## 4. DB 스키마 상세

### Alembic 마이그레이션 이력

| 버전 | 설명 |
|------|------|
| 0001 | `posts.mention_tags` JSON 컬럼 |
| 0002 | `blocks`, `conversations`, `direct_messages` |
| 0003 | `suspended_until`, `warning_count`, `reports` 카테고리, `user_warnings` |
| 0004 | `users.fcm_token` |
| 0005 | `users.certified_nickname`, `users.school_short_name`, `posts.nickname_type` |
| 0006 | `academies`, `academy_reviews` 테이블 |
| 0007 | `profanity_words` 테이블 |
| 0008 | `users.member_grade`, `parent_captures` 테이블 |
| 0009 | `users.admin_username`, `users.admin_password_hash` |
| 0010 | `invite_links` 테이블 |
| 0011 | `admin_notices` 테이블 |
| 0012 | `schools` 테이블 (NEIS 학교 목록) |
| 0013 | `academy_reviews.subjects` JSON 컬럼 |
| 0014 | `users.manner_score` 기본값 100으로 수정 |
| 0015 | `users.admin_username` nullable 수정 |
| 0016 | `academy_reviews` 복수 필드 지원 (teacher_styles, subjects) |
| 0017 | `user_children` 테이블, `users.active_child_id` |
| 0018 | `users.academy_review_count` |
| 0019 | 다자녀 마이그레이션 (기존 school_code → user_children 복사) |
| 0020 | `academy_reviews.is_seed` 컬럼 |
| 0021 | `users.kakao_id`, `users.is_trusted` |
| 0022 | `auth_captures.image_data`(BYTEA), `image_content_type` 추가, `s3_key` nullable 전환 (Supabase Storage → DB 직접 저장) |
| 0023 | `auth_captures.input_school_type`, `input_region` 추가 (모델에는 있었으나 마이그레이션이 누락되어 있던 컬럼 — 프로덕션 캡처 업로드 500의 실제 원인) |

### 주요 테이블 (추가/변경된 것 중심)

#### `auth_captures` — 알림장 캡처 인증

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | |
| `user_id` | FK → users | |
| `s3_key` | String, nullable | 레거시 Supabase Storage 경로 (하위호환용, 신규 행은 미사용) |
| `image_data` | BYTEA, nullable | 캡처 이미지 원본. 심사(승인/반려) 시 같은 트랜잭션에서 비움 |
| `image_content_type` | String(30), nullable | |
| `school_code` | String(20) | |
| `school_name` | String(100) | |
| `grade` | Integer | |
| `class_num` | Integer | nullable |
| `school_type` | String(20) | |
| `region` | String(50) | |
| `capture_type` | String(20) | initial / child_add |
| `status` | String(20) | pending / approved / rejected |
| `reviewed_by` | Integer | 관리자 user_id |
| `reviewed_at` | DateTime | |
| `created_at` | DateTime | |

#### `invite_links` — 초대 링크

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | |
| `token` | String UNIQUE | URL 토큰 (UUID) |
| `school_code` | String(20) | |
| `school_name` | String(100) | |
| `school_type` | String(10) | |
| `created_by` | FK → users | 발급자 |
| `used_by` | FK → users | 사용자 (1회 제한) |
| `expires_at` | DateTime | |
| `created_at` | DateTime | |

#### `admin_notices` — 관리자 공지

| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | Integer PK | |
| `author_id` | FK → users | 관리자 계정 |
| `title` | String(200) | |
| `content` | Text | |
| `target_region` | String(30) | 특정 지역 타겟 (nullable) |
| `target_school_code` | String(20) | 특정 학교 타겟 (nullable) |
| `board_type` | String(20) | |
| `is_pinned` | Boolean | |
| `created_at` | DateTime | |

---

## 5. API 엔드포인트 목록

Base URL: `https://momstalk-backend.onrender.com/api/v1` (프로덕션)  
인증 방식: `Authorization: Bearer {access_token}`

### 인증 (auth)

| Method | Path | 설명 |
|--------|------|------|
| POST | `/auth/kakao` | 카카오 액세스 토큰 → JWT 발급 |
| POST | `/auth/refresh` | Refresh Token → 새 Access Token |
| GET | `/auth/me` | 내 프로필 조회 (children 포함) |
| PATCH | `/auth/me/nickname` | 닉네임 수정 |
| DELETE | `/auth/me` | 회원 탈퇴 |
| GET | `/auth/invite/{token}` | 초대 링크 정보 조회 (만료/사용 여부 포함) |
| POST | `/auth/invite/use` | 초대 링크 사용 (가입 또는 자녀 추가) |
| POST | `/auth/capture/upload` | 알림장 캡처 이미지 업로드 (DB BYTEA 직접 저장) |
| POST | `/auth/me/children` | 자녀 즉시 추가 — is_trusted/admin 전용(사진 인증 생략) |
| POST | `/auth/me/active-child/{child_id}` | 활성 자녀 전환 |
| DELETE | `/auth/me/children/{child_id}` | 자녀 삭제 |
| PATCH | `/auth/me/profile` | 지역/학교/학년 변경 (월 1회 제한, is_trusted는 무제한) |

### 관리자 (admin) — Flutter 인앱

| Method | Path | 설명 |
|--------|------|------|
| GET | `/admin/captures` | 캡처 심사 목록 |
| POST | `/admin/captures/{id}/approve` | 캡처 승인 |
| POST | `/admin/captures/{id}/reject` | 캡처 거부 |
| GET | `/admin/users` | 유저 목록 (닉네임/kakao_id 검색) |
| POST | `/admin/users/{id}/grant-trust` | is_trusted 부여 |
| POST | `/admin/users/{id}/revoke-trust` | is_trusted 해제 |
| GET | `/admin/stats` | 통계 (가입자/게시글/학원 후기) |
| GET | `/admin/invite-links` | 초대 링크 목록 |
| POST | `/admin/invite-links` | 초대 링크 생성 |

### 학교·학원 검색 (schools)

| Method | Path | 설명 |
|--------|------|------|
| GET | `/schools/search?q={}` | NEIS API 학교 검색 |
| GET | `/schools/academies/search?q={}&region={}&subject={}` | NEIS API 학원 검색 |

### 게시글 (posts)

| Method | Path | 설명 |
|--------|------|------|
| GET | `/posts?board_type={}&page={}&size={}&q={}` | 게시글 목록 |
| POST | `/posts` | 게시글 작성 |
| GET | `/posts/{id}` | 게시글 상세 |
| PATCH | `/posts/{id}` | 게시글 수정 |
| DELETE | `/posts/{id}` | 게시글 소프트 삭제 |
| POST | `/posts/{id}/like` | 좋아요 토글 (목록 화면에서도 탭 가능, 작성자 매너온도 반영) |
| POST | `/posts/{id}/scrap` | 스크랩 토글 |
| GET | `/posts/{id}/comments` | 댓글 목록 |
| POST | `/posts/{id}/comments` | 댓글 작성 |
| POST | `/posts/{id}/comments/{cid}/like` | 댓글 좋아요 토글 |
| DELETE | `/posts/{id}/comments/{cid}` | 댓글 삭제 |

### 학원 (academies)

| Method | Path | 설명 |
|--------|------|------|
| GET | `/academies?region={}&subject={}&school_type={}` | 학원 목록 |
| GET | `/academies/{id}` | 학원 상세 |
| GET | `/academies/review-quota` | 가림 처리 없이 열람 가능한 "학원 개수" 현황 (게시판 상단 배너용) |
| GET | `/academies/{id}/reviews` | 학원 후기 목록 (해금 여부에 따라 전체/미리보기) |
| POST | `/academies/{id}/reviews` | 학원 후기 작성 |

### DM / 실시간 (conversations, stream)

| Method | Path | 설명 |
|--------|------|------|
| GET | `/conversations` | 내 대화 목록 |
| POST | `/conversations/{other_user_id}` | 대화방 생성 또는 기존 반환 |
| GET | `/conversations/{id}/messages` | 메시지 목록 |
| POST | `/conversations/{id}/messages` | 메시지 전송 |
| GET | `/stream` | SSE 실시간 이벤트 스트림 |

---

## 6. 화면 구성 및 UI 레이아웃

### 6-1. 전체 네비게이션 구조

```
앱 진입
  ├── [미로그인] → 카카오 로그인 화면
  ├── [lurker/auth_pending] → 학교 게시판 제한 접근
  └── [member] → 전체 기능 접근

바텀 네비게이션 (5탭, StatefulShellRoute.indexedStack — 탭 이동해도 각 화면 State 유지)
  ├── [지역]   — RegionBoardScreen (region 게시판 + 공지 상단바)
  ├── [학교]   — SchoolBoardScreen (school/grade TabBar, 다자녀: 드롭다운으로 자녀 전환)
  ├── [학원]   — AcademyScreen (학원 검색 + 후기 DB)
  ├── [대화]   — DmListScreen
  └── [내정보] — ProfileScreen (프로필 / 자녀 관리 / 학교 변경)

주요 화면 라우트:
  /auth/login               카카오 로그인
  /auth/school-select       학교 선택 (초대 링크 없이 접근 시)
  /auth/capture             알림장 캡처 업로드
  /auth/pending             인증 심사 중 대기 화면
  /invite/{token}           초대 링크 가입/자녀 추가 화면
  /region                   지역 게시판 (바텀탭)
  /school                   학교 게시판 (바텀탭)
  /board/:postId            게시글 상세
  /board/write              글쓰기
  /academy                  학원 탭
  /academy/:academyId       학원 상세
  /profile/add-child        자녀 추가
  /my                       내정보 (바텀탭)
  /admin                    관리자 화면 (admin only)

※ IndexedStack 구조상 다른 화면(글쓰기, 자녀 추가, 학교 변경 등)에서 데이터를
   바꾸고 돌아와도 목록 화면이 자동으로는 갱신되지 않는다. 이를 위해
   `core/refresh_bus.dart`의 `boardRefreshSignal` 공용 신호로 "돌아왔을 때
   최신 상태로 갱신"과 "이미 선택된 탭 재탭 = 새로고침"을 명시적으로 구현했다.
```

### 6-2. 계정 상태별 접근 제어

| 상태 | region 게시판 | school 게시판 | grade 게시판 | 글쓰기 | 학원 후기 |
|------|-------------|-------------|------------|--------|----------|
| lurker | ❌ 잠금 UI | ✅ 읽기만 | ✅ 읽기만 | ❌ | ❌ |
| auth_pending | ❌ 잠금 UI | ❌ 잠금 UI | ❌ 잠금 UI | ❌ | ❌ |
| member | ✅ | ✅ | ✅ | ✅ | ✅ |

### 6-3. 다자녀 학교 탭 전환

- 자녀가 2명 이상: 게시판 AppBar에 드롭다운으로 자녀별 학교 전환
- 드롭다운 선택 시 `POST /auth/me/active-child/{child_id}`로 서버에 즉시 반영하고, `boardRefreshSignal`을 bump해 지역/학원/내정보 탭도 함께 갱신 (어느 화면에서 자녀를 바꾸든 모든 탭이 같은 활성 자녀 기준으로 동기화됨)
- `/auth/me` 등 프로필 응답 자체가 activeChild 기준으로 정규화되어 내려오므로, 각 화면은 `profile['school_name']` 등을 그대로 신뢰하면 된다 (3-4절 참고)

---

## 7. 게시판 구조 — 선택적 실명제

### 게시판 유형 (board_type)

| board_type | 탭 표시명 | 닉네임 정책 | 접근 범위 |
|-----------|----------|------------|----------|
| `region` | 지역명 | 닉네임 유형 선택 가능 | 동일 `region` 유저들의 글 |
| `school` | 학교명 | 닉네임 유형 선택 가능 | 동일 `school_code` 유저들의 글 |
| `grade` | N학년 | 닉네임 유형 선택 가능 | 동일 학교 + 동일 학년 |
| `free` | 전체 | 닉네임 유형 선택 가능 | 모든 글 |

### 관리자 공지 노출

- 관리자가 작성한 공지는 해당 region/school 게시판 상단 고정
- 게시글 목록에서 작성자 표시: `is_admin = true` → "관리자" 배지

---

## 8. 학원 후기 시스템

### 후기 작성 템플릿

| 항목 | 입력 방식 | 옵션 |
|------|----------|------|
| 과목 | 다중 선택 | 수학 / 영어 / 과학 / 국어 / 기타 |
| 선생님 스타일 | 다중 선택 | 꼼꼼형 / 자유형 / 엄격형 |
| 숙제량 | 별점 선택 | ★☆☆ / ★★☆ / ★★★ |
| 성적 향상도 | 4단 선택 | 많이 올랐어요 / 조금 올랐어요 / 그대로에요 / 내렸어요 |
| 총평 | 200자 이내 자유 입력 | |
| 공개 방식 | 라디오 선택 | 인증 닉네임 / 완전 익명 |

### 학원 후기 필터

- 지역 / 과목 / 학교급 필터
- 학년 필터: 초등(1~6학년) / 중등·고등(1~3학년) — 학교급에 따라 동적 표시

### 후기 열람 제한 (기여 기반 언락) — "학원 개수" 단위

과거에는 "한 학원 안에서 몇 개의 후기를 볼 수 있는지"를 제한했으나(학원당 열람 개수), 현재는 **가림 처리 없이 전체 열람 가능한 "학원의 개수"**를 사용자가 작성한 후기 수에 따라 늘려주는 방식으로 바뀌었다.

| 내 작성 후기 수 | 열람 가능 학원 수 |
|----------------|------------------|
| 0건 | 1곳 |
| 1건 이상 | 5곳 |
| 5건 이상 | 무제한 |

- `AcademyReviewUnlock` 테이블에 사용자가 한 번 열람 해금한 학원을 기록 — 이후에도 계속 가림 처리 없이 볼 수 있음 (슬롯을 영구 소비)
- 잠긴 학원은 **기본 소개(seed 후기) + 사용자 후기 모두** 상단 한 줄 미리보기만 노출 (전체 내용은 후기 작성 시 해금)
- `GET /academies/review-quota`가 게시판 상단 배너에 표시할 전역 해금 현황(해금한 학원 수/한도, 다음 해금까지 필요한 후기 수)을 제공

---

## 9. 신고 시스템

- 신고 대상: 게시글 / 댓글 / 학원 후기
- 동일 유저 중복 신고 차단 (DB UNIQUE 제약)
- 누적 5건 → `is_hidden = True` 자동 블라인드
- Flutter 인앱 관리자 화면에서 검토·처리

---

## 10. 차단 및 숨기기

- `POST /users/{target_id}/block` — 차단 등록
- `DELETE /users/{target_id}/block` — 차단 해제
- `GET /users/blocks` — 차단 목록 조회
- 게시글 목록 조회 시 차단된 유저의 게시글 자동 필터링

### 보완 필요

| 항목 | 설명 |
|------|------|
| 댓글 차단 필터링 | 현재 게시글만 필터, 댓글 미적용 |
| DM 차단 연동 | 차단된 유저에게 DM 발신 가능 (미적용) |

---

## 11. 1:1 대화 (DM)

- 게시글/댓글 더보기 → "대화하기" → 대화방 자동 생성
- 메시지 목록 조회 시 자동 읽음 처리
- SSE 실시간 수신, FCM 푸시
- **보완 필요**: 차단 유저 DM 발신 차단, 채팅방 내 SSE 실시간화

---

## 12. 계정 정지 시스템

**계정 상태 판단 순서 (`get_current_user` 의존성 주입):**

```
1. JWT 유효성 검사 → 실패 시 401
2. 유저 존재 여부 → 없으면 401
3. is_banned == True → 403 "영구 정지된 계정입니다."
4. suspended_until > now → 403 + X-Suspend-Until 헤더
5. 정상 → 유저 객체 반환
```

---

## 13. 스레드 익명화

| 조건 | 표시 레이블 |
|------|------------|
| 익명 댓글 + 게시글 작성자 본인 | "글쓴이" |
| 익명 댓글 + 최초 등장 타인 | "익명1" |
| 익명 댓글 + 두 번째 등장 타인 | "익명2" |
| 인증 닉네임 댓글 | `certified_nickname` 표시 |
| 본인이 작성한 댓글 | `is_mine: true` → "나" 뱃지 |

서버 런타임 계산 — DB에 저장하지 않음.

---

## 14. 금칙어 필터링

- `backend/app/core/profanity.py`
- 게시글/댓글 **작성 시** 서버 검사 → 포함 시 400
- **보완 필요**: 게시글 수정 시 미적용

---

## 15. 푸시 알림 (FCM)

| 이벤트 | 수신자 | 알림 내용 |
|--------|--------|----------|
| 내 게시글에 댓글 | 게시글 작성자 | "새 댓글이 달렸어요" |
| DM 수신 | DM 수신자 | "{닉네임}님의 메시지" |
| 캡처 승인 | 사용자 | "정회원으로 승인되었습니다" |

---

## 16. 실시간 DM (SSE)

- `backend/app/core/sse_manager.py`: `user_id → asyncio.Queue` 인메모리
- 25초 heartbeat
- **주의**: 단일 인스턴스 전용. Render 무료 플랜에서 정상 동작.

---

## 17. 보안 설계

### 구현된 보안 항목

| 항목 | 상태 |
|------|------|
| 카카오 OAuth (비밀번호 비저장) | ✅ |
| JWT Bearer 인증 | ✅ |
| Access Token 60분 만료 | ✅ |
| Refresh Token 30일 만료 | ✅ |
| 자동 토큰 갱신 (Dio 인터셉터) | ✅ |
| CORS: `allow_origins=["*"]`, `allow_credentials=False` | ✅ |
| 본인 게시글만 수정/삭제 검증 | ✅ |
| 중복 신고/좋아요 차단 (DB UNIQUE) | ✅ |
| Soft Delete | ✅ |
| 영구/기간 정지 차단 (403) | ✅ |
| 서버 금칙어 필터 | ✅ |
| is_trusted 인증 면제 권한 (관리자 부여) | ✅ |

### CORS 설계 결정

Bearer 토큰 인증 방식(쿠키 미사용)이므로 `allow_credentials=False` + `allow_origins=["*"]`가 올바른 설정이다. 특정 도메인 화이트리스트는 불필요하며 Vercel 도메인 변경에도 대응된다.

### 보완 필요 항목

| 항목 | 우선순위 |
|------|----------|
| 토큰 블랙리스트 (로그아웃 시 Refresh Token 무효화) | 🟡 중간 |
| 게시글 수정 금칙어 검사 | 🟡 중간 |
| 학원 후기 허위 광고 탐지 | 🟡 중간 |

---

## 18. 관리자 시스템 — Flutter 인앱 + Streamlit

### Flutter 인앱 관리자 (기본 운영 도구)

`/admin` 라우트 진입 시 관리자 로그인 필요 (`member_grade = 'admin'`).

| 메뉴 | 기능 |
|------|------|
| 홈 | 통계 (가입자/게시글/학원 후기 수) |
| 캡처 심사 | 대기 중 캡처 목록 → 승인/거부 |
| 유저 관리 | 유저 검색 (닉네임/kakao_id), is_trusted 부여/해제, 정지 |
| 초대 링크 | 링크 생성/목록 |
| 학원 후기 | 시드 데이터 관리 |
| 로그/통계 | 활동 로그 |

### is_trusted (인증 면제 권한)

- 관리자가 특정 유저에게 부여
- 캡처 업로드 시 관리자 심사 없이 즉시 `approved` 처리
- 자녀 추가 인증도 동일하게 즉시 승인

### Streamlit 관리자 (보조 도구)

- `admin/` 디렉터리
- 금칙어 관리, 신고 처리 보조, B2B 학원 관리
- Docker Compose 별도 서비스 (로컬 개발 전용)

---

## 19. 수익화 모델

| 트랙 | 개시 시점 | 내용 | 목표 매출 (Year 2) |
|------|----------|------|-------------------|
| **BM1 학원 B2B 프로필** | Month 12 | 월 3~10만원 (규모별 차등) | 100곳 × 월 5만원 = 월 500만원 |
| **BM2 타겟 네이티브 광고** | Month 18 | 지역+학년 검증 타겟 | MAU 1만 × CPM 5,000원 |
| **BM3 B2C 프리미엄 구독** | Month 24 | 최근 3개월 학원 랭킹, 타 지역 열람 | MAU 5만 × 5% × 3,900원 |

### 운영 비용 (현재 무료 구간)

| 항목 | 비용 |
|------|------|
| Vercel (Flutter Web) | 무료 |
| Render (FastAPI) | 무료 (콜드스타트 있음) / $7/월 (Starter) |
| Supabase (PostgreSQL) | 무료 500MB |
| 카카오 로그인 | 무료 |
| NEIS API | 무료 |

---

## 20. 로드맵 및 KPI

| Phase | 기간 | 핵심 목표 | KPI |
|-------|------|----------|-----|
| **Phase 1** | Month 1~6 | PWA 출시 + 부산 집중 시드 콘텐츠 | 가입자 1,000명 / MAU 500명 / 학원 후기 1,000건 |
| **Phase 2** | Month 7~12 | 전국 오픈 + MAU 성장 | MAU 3,000명 / iOS 앱 출시 |
| **Phase 3** | Month 13~18 | iOS 앱 + 수익화 시작 | MAU 5,000명 / B2B 유료 50곳 |
| **Phase 4** | Month 19~36 | Android + 스케일업 | MAU 5만명 / 흑자 전환 |

---

## 21. 미구현 / 보완 필요 항목

### 출시 전 필수 (P0) 🔴

| 항목 | 설명 |
|------|------|
| 댓글 차단 필터링 | 현재 게시글만 필터, 댓글 미적용 |
| DM 차단 연동 | 차단된 유저에게 DM 발신 가능 (미차단) |
| 게시글 수정 금칙어 검사 | 수정 시 미적용 |
| 개인정보처리방침 · 이용약관 | 법률 자문 후 게시 필수 |

### 핵심 기능 (P1) 🟡

| 항목 | 설명 |
|------|------|
| 채팅방 내 SSE 실시간화 | 현재 채팅방 내부는 전송 후 수동 갱신 |
| 알림 탭 | 댓글/승인/정지 인앱 알림 목록 |
| 토큰 블랙리스트 | 로그아웃 시 Refresh Token 무효화 |
| 학원 후기 이의 신청 UI | 명예훼손 리스크 관리 |
| 이미지 첨부 (게시글) | 아직 미지원. 캡처 업로드처럼 DB BYTEA 직접 저장 방식이 이 규모에서는 더 간단할 수 있음(22-2절) |
| 관측성(Observability) | Sentry 등 에러 트래킹 부재 — 이번 세션의 여러 버그(스키마 드리프트, CORS 순서, nickname_type 검증)가 모두 사용자 신고로만 발견됨 (23장 참고) |

> ✅ 완료: 게시판 인기순/최신순 정렬, 무한 스크롤(커서 기반), 게시글 좋아요(목록에서 바로 탭 가능), 학원 후기 열람 제한(기여 기반 언락, 8절 참고)

### 스케일업 (P2) 🔵

| 항목 | 설명 |
|------|------|
| iOS 네이티브 앱 | MAU 5,000 달성 후 개발 |
| Android 앱 | Phase 4 |
| B2B 학원 프로필 구독 | Month 12 수익화 |
| SSE → Redis Pub/Sub | 멀티 인스턴스 배포 시 전환 |
| 다크 모드 | 미지원 |

---

## 22. 인프라 및 배포

### 현재 프로덕션 구성

| 역할 | 서비스 | URL |
|------|--------|-----|
| **Flutter Web PWA** | Vercel | `https://momstalk.vercel.app` (또는 커스텀 도메인) |
| **FastAPI 백엔드** | Render Web Service | `https://momstalk-backend.onrender.com` |
| **PostgreSQL** | Supabase | `postgresql+asyncpg://...@db.supabase.co:5432/postgres` |
| **캡처 이미지 저장** | Postgres BYTEA (`auth_captures.image_data`) | Supabase Storage 미사용 |

### Render 자동 배포

- `main` 브랜치 push → Render 자동 빌드/배포
- `start.sh` 실행 순서:
  1. Alembic 버전 사전 동기화 (복수 헤드 정리)
  2. `alembic upgrade head`
  3. `uvicorn app.main:app --host 0.0.0.0 --port 8000`

### 로컬 개발 구성 (Docker Compose)

| 서비스 | 포트 | 역할 |
|--------|------|------|
| `momstalk_backend` | 8000 | FastAPI |
| `momstalk_db` | 5432 | PostgreSQL (단일 통합 DB) |
| `momstalk_redis` | 6379 | Rate Limit |
| `momstalk_admin` | 8501 | Streamlit (보조 관리자) |

### 환경변수

```ini
# DB
DATABASE_URL=postgresql+asyncpg://...

# 보안
SECRET_KEY={64자 이상 랜덤}

# 카카오
KAKAO_CLIENT_ID={REST API 키}
KAKAO_CLIENT_SECRET={시크릿 키}

# NEIS
NEIS_API_KEY={교육부 나이스 오픈API 키}

# Supabase (DB 연결에만 사용 — 캡처 이미지는 더 이상 Supabase Storage를 쓰지 않음)
SUPABASE_URL=https://{project-id}.supabase.co
SUPABASE_KEY={service_role 키}

# FCM
FCM_SERVICE_ACCOUNT_JSON={Firebase 서비스 계정 JSON 한 줄}

# 앱
DEBUG=false
# CORS: allow_origins=["*"], allow_credentials=False (Bearer 토큰 방식)
# 주의: CORSMiddleware는 다른 커스텀 미들웨어(글로벌 rate limit 등)보다
# 반드시 나중에 add_middleware()해야 최외곽(outermost)에서 모든 응답을 감싼다.
```

---

## 23. 활성화 및 시스템 개선 방안

> 실사용자 온보딩이 시작된 시점(2026-07-06)에 정리. 이번 세션에서 캡처 업로드가
> 프로덕션에서 사실상 **계속 실패하고 있었다**는 것을 발견했다 — 원인은 마이그레이션
> 누락으로 인한 500 에러였는데, 클라이언트에는 일관되게 "네트워크 오류"로만 보여
> 몇 주간 원인 파악이 어려웠을 가능성이 높다. 이런 사각지대를 줄이는 것이 활성화의
> 전제조건이라는 문제의식으로 아래 방안들을 정리했다.

### 23-1. 즉시 점검 — 이번 세션에서 고친 항목들이 실제로 반영됐는지

신규 유저 유입이 시작된 지금, 아래 항목이 **배포 후 실제로 동작하는지** 최우선으로 확인해야 한다. 문서만 고치고 배포가 안 되면 활성화 방안은 의미가 없다.

| 확인 항목 | 확인 방법 |
|-----------|-----------|
| Alembic 0022/0023이 프로덕션에 적용됐는지 | Render 배포 로그에서 `alembic upgrade head` 결과 확인, 또는 `alembic current` |
| 캡처 업로드가 실제로 성공하는지 | 테스트 계정으로 자녀 학교 인증 1회 실제 수행 |
| CORS 미들웨어 순서 수정이 반영됐는지 | 배포된 서버에 curl로 OPTIONS 프리플라이트 확인 |
| 가입→인증→첫 게시글 작성까지 전체 퍼널이 끊기지 않는지 | 신규 계정으로 처음부터 끝까지 1회 실행 |

### 23-2. 관측성(Observability) 부재 — 가장 시급한 시스템 개선

이번 세션에서 발견한 버그들(스키마 드리프트로 인한 500, CORS 순서 오류로 인한 조기 반환 차단, `nickname_type` 검증 실패, TabBarView 상태 유실)은 **전부 사용자가 스크린샷을 보내줘서** 알게 된 것이다. 서버 쪽에서 자동으로 감지된 것은 하나도 없다. 실사용자가 늘어나면 이 방식은 확장되지 않는다.

**우선순위 순 제안:**
1. **에러 트래킹 도입 (Sentry 무료 티어 등)** — FastAPI 미들웨어로 unhandled exception을 자동 수집. 이번 `UndefinedColumn` 500 같은 사고를 사용자 신고 없이 몇 분 안에 감지할 수 있었을 것.
2. **구조화 로깅 + 헬스체크 모니터링** — `/health`를 외부 uptime 모니터(UptimeRobot 무료 등)로 주기 핑 → Render 콜드스타트/다운타임을 사전 인지.
3. **CI에서 모델↔마이그레이션 드리프트 자동 검출** — `alembic check` 또는 `alembic revision --autogenerate --check`를 CI에 추가해, 모델 필드 추가 시 마이그레이션 누락을 배포 전에 막는다 (이번 0023 사고의 재발 방지).
4. **핵심 플로우 스모크 테스트** — 캡처 업로드, 게시글 작성, 로그인 흐름 등 "이번에 깨졌던 것들" 위주로 최소한의 E2E 테스트를 CI에 추가.

### 23-3. 온보딩 퍼널 개선 — 초대 → 인증 → 첫 활동

가입 퍼널이 (초대 링크 클릭 → 카카오 로그인 → 학교 인증 → 관리자 승인 → 첫 게시글)로 길고, 그중 "학교 인증"(사진 업로드) 단계가 최근까지 실질적으로 깨져 있었을 가능성을 고려하면, **이 구간의 이탈률을 먼저 계측**해야 한다.

- **퍼널 계측**: `invite_links.used_by` 채워짐 → `auth_captures` 생성 → `status=approved` → 첫 `posts` 작성까지 각 단계 전환율을 관리자 통계(`/admin/stats`)에 추가. 지금은 가입자/게시글 총량만 보이고 어느 단계에서 이탈하는지 알 수 없다.
- **인증 대기 체감 시간 단축**: 관리자 심사가 1인 운영 체제라 즉시 처리가 어렵다. 심사 대기 중에도 school/grade 게시판 읽기는 이미 허용되어 있으니(lurker 권한), 대기 화면에서 "심사 중에도 둘러볼 수 있어요" 식으로 school 게시판 미리보기를 더 적극적으로 유도.
- **초대 기반 신뢰 전파 확대**: 정회원의 초대로 가입한 유저는 `is_trusted`에 준하는 완화된 심사(예: 사진 인증 없이 학교 정보만으로 임시 열람 허용 후 사후 검증)를 검토할 만하다. 지금은 초대와 `is_trusted`가 별개 축인데, "신뢰할 만한 사람이 초대한 사람"이라는 신호를 심사 우선순위나 자동 승인 조건에 반영하면 병목(관리자 수동 심사)을 줄일 수 있다.
- **카카오 공유 도달률**: 모바일 브라우저에서 카카오톡 공유가 조용히 실패하던 버그를 이번에 고쳤다(웹 open helper). 초대 링크가 앱의 주요 성장 루프이므로, 배포 후 공유 성공률을 실제로 확인할 것.

### 23-4. 콘텐츠 콜드스타트 — 학원 후기 플라이휠

- 학원 후기 언락 시스템(8절)은 "후기를 쓰면 더 많이 볼 수 있다"는 유인 구조가 이미 있다. 다만 **첫 방문자 입장에서 왜 후기를 써야 하는지**가 화면 진입 즉시 보이지 않으면 이 유인이 작동하지 않는다 — 학원 상세 화면 진입 시 잠긴 학원 비율(예: "이 지역 학원 중 82%가 아직 잠겨있어요")처럼 구체적 숫자로 동기를 부여하는 문구를 상단 배너에 추가하는 것을 고려.
- Seed 후기(AI 요약)로 콜드스타트를 방어하고 있지만, seed 후기 커버리지가 낮은 지역/학원은 후기 자체가 없어 언락 유인도 약하다 — 시드 확장 우선순위를 "신규 유저 유입 지역"에 맞춰 재조정.

### 23-5. 1인 운영 관점의 리스크

- **is_trusted 오남용 방지**: 사진 인증을 완전히 건너뛰는 권한이므로, 부여 대상/사유를 `AdminAction` 로그로 남기고 있는지 확인하고(이미 남김), 주기적으로 `is_trusted=true` 목록을 재검토하는 루틴을 관리자 체크리스트에 추가.
- **Render 무료 티어 콜드스타트**: MAU가 늘면 콜드스타트로 인한 첫 요청 실패가 신규 유저의 첫인상을 해칠 수 있다. 유료 플랜(Starter, $7/월) 전환 시점을 "일 평균 활성 유저 수" 같은 구체적 트리거로 미리 정해두는 것을 권장.
- **단일 인스턴스 SSE**: 현재 구조는 인스턴스 1개 전제. MAU가 늘어 오토스케일이 필요해지는 시점에 DM 실시간성이 먼저 깨질 것 — Redis Pub/Sub 전환은 로드맵 P2에 있지만, 트리거 조건(동시 접속자 수 등)을 미리 정의해두면 대응이 늦지 않는다.

---

*이 문서는 2026-07-06 기준 구현 상태를 반영합니다. (Alembic 0023, Vercel+Render+Supabase 배포)*
