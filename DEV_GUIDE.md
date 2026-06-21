# 맘스톡 — 로컬 개발 실행 가이드

## 사전 요구사항

| 도구 | 버전 | 확인 명령 |
|------|------|-----------|
| Docker Desktop | 최신 | `docker --version` |
| Flutter | 3.x 이상 | `flutter --version` |
| Chrome | 최신 | — |
| Python | 3.11 이상 | `python --version` (관리자 로컬 실행 시) |

---

## 1단계: Docker Desktop 시작

시스템 트레이에서 Docker Desktop을 실행하고 고래 아이콘이 초록색이 될 때까지 대기합니다.

---

## 2단계: 백엔드 실행

프로젝트 루트에서 실행합니다.

```bash
cd c:\projects\momstalk
docker-compose up -d
```

정상 실행 확인:

```bash
curl http://localhost:8000/health
# {"status":"ok","app":"MomsTalk"}
```

| 서비스 | 주소 |
|--------|------|
| FastAPI 백엔드 | http://localhost:8000 |
| API 문서 (Swagger UI) | http://localhost:8000/docs |
| PostgreSQL 서비스 DB | localhost:5432 |
| PostgreSQL 인증 DB | localhost:5433 |
| Redis | localhost:6379 |

백엔드 로그 확인:

```bash
docker logs momstalk_backend -f
```

---

## 3단계: DB 마이그레이션

최초 실행 또는 마이그레이션 파일 추가 시 실행합니다.

```bash
docker exec momstalk_backend alembic upgrade head
```

마이그레이션 현황 확인:

```bash
docker exec momstalk_backend alembic current
```

---

## 4단계: Flutter 웹 실행

```bash
cd c:\projects\momstalk\mobile
flutter pub get       # 최초 1회 또는 pubspec.yaml 변경 시
flutter run -d chrome --web-port 3000
```

브라우저에서 자동으로 열립니다. 수동으로 접속하려면:

```
http://localhost:3000
```

---

## 5단계: 관리자 대시보드 (Streamlit)

로컬 개발 시에는 Docker 없이 직접 실행합니다.

```bash
cd c:\projects\momstalk\admin
# 처음 한 번
pip install -r requirements.txt
cp .env.example .env       # .env 편집 후 DATABASE_URL 설정

streamlit run app.py --server.port 8501
```

브라우저에서 http://localhost:8501 에 접속합니다.

> 기본 비밀번호: `.env`의 `ADMIN_PASSWORD` 값 (기본: `change_me_before_deploy`)

---

## 6단계: 회원가입 테스트 흐름 (v3 카카오 로그인)

로컬에서는 `DEBUG=true` 상태에서 `/auth/dev/login` 엔드포인트를 사용합니다.

```bash
# 테스트 유저 생성 (Swagger UI 또는 curl)
curl -X POST http://localhost:8000/api/v1/auth/dev/login \
  -H "Content-Type: application/json" \
  -d '{
    "phone_number": "01012345678",
    "region": "강남구",
    "school_code": "B100000001",
    "school_name": "테스트초등학교",
    "grade": 3,
    "school_type": "elementary"
  }'
```

카카오 로그인 전체 흐름 테스트:
1. Flutter 앱 실행 → 카카오 로그인 화면
2. 카카오 연동 → JWT 발급 (lurker 상태)
3. 학교 선택 → 알림장 캡처 업로드
4. 관리자 대시보드(localhost:8501)에서 캡처 승인
5. FCM 푸시 알림 수신 → `member` 승급 확인

---

## 재시작 / 정지

**백엔드만 재시작:**
```bash
docker-compose restart backend
```

**전체 정지:**
```bash
docker-compose down
```

**데이터 포함 완전 삭제:**
```bash
docker-compose down -v
```

---

## 자주 발생하는 문제

### 포트 3000 이미 사용 중
```bash
netstat -ano | findstr :3000
taskkill /PID <PID번호> /F
```

### Docker가 실행 중이 아님
Docker Desktop을 먼저 시작한 뒤 `docker info`로 확인합니다.

### 로그인 후 무한 로딩
브라우저 개발자 도구(F12) → Application → Local Storage → `localhost:3000` 항목을 모두 삭제한 뒤 새로고침합니다.

### 카카오 로그인 오류 (flutter: KakaoClientException)
`constants.dart`의 `kakaoNativeAppKey`가 `YOUR_KAKAO_NATIVE_APP_KEY` 그대로인 경우입니다. 카카오 개발자 콘솔에서 네이티브 앱 키를 발급 후 교체하세요.

### 403 Forbidden — 게시판 접근 불가
FastAPI `HTTPBearer()`는 Authorization 헤더가 없을 때 **401이 아닌 403**을 반환합니다. 토큰이 저장되지 않은 것이 원인입니다.
- 브라우저 LocalStorage(`momstalk_access_token` 키) 값 확인
- 값이 없으면 로그아웃 후 재로그인
- 개발 중이라면 `/auth/dev/login` 으로 토큰 재발급

### `FormatException: write` 오류
go_router 라우트 순서 문제입니다. `/board/write`가 `/board/:postId` 보다 **아래**에 있으면 `write`가 postId 파라미터로 파싱되어 `int.parse('write')`에서 오류가 발생합니다.

`router.dart`에서 정적 경로는 항상 파라미터 경로 앞에 위치해야 합니다:
```dart
// ✅ 올바른 순서
GoRoute(path: '/board/write', ...),   // 먼저
GoRoute(path: '/board/:postId', ...),  // 나중
```

### 한글 텍스트 입력 시 □× 두부문자 (Tofu characters)
Flutter Web 기본 폰트(Roboto)가 한글을 지원하지 않아 폰트 로딩 전 짧은 시간 동안 두부문자가 표시됩니다.

현재 적용된 해결책:
1. `pubspec.yaml` — `google_fonts: ^6.2.1`
2. `mobile/lib/core/theme.dart` — `textTheme: GoogleFonts.notoSansKrTextTheme()`
3. `mobile/web/index.html` — Noto Sans KR CSS 사전 로드 (`display=block`)

재발 시: `flutter pub get` 후 `flutter run -d chrome --web-port 3000`으로 재빌드하세요.

---

## 아키텍처 결정 사항

### 토큰 저장소 (플랫폼 분기)
`kIsWeb`으로 플랫폼을 판별해 저장소를 분리합니다 (`mobile/lib/core/api_client.dart`):

| 플랫폼 | 저장소 | 실제 위치 |
|--------|--------|-----------|
| Web | `SharedPreferences` | 브라우저 localStorage |
| Android | `FlutterSecureStorage` (EncryptedSharedPreferences) | Android Keystore |
| iOS | `FlutterSecureStorage` | iOS Keychain |

Web에서 `FlutterSecureStorage`를 쓰면 Web Crypto API 의존성 + IndexedDB 비동기 초기화 타이밍 이슈로 불안정했습니다.

코드에서 `tokenStorageProvider`를 통해 접근하며, `secureStorageProvider`는 하위 호환 별칭입니다.

### 지역 표시 단위 (NEIS 주소 파싱)
`ORG_RDNMA` 주소 필드에서 지역을 추출할 때 행정구역 단계를 구분합니다:

| 도/시 유형 | 반환 단위 | 예시 |
|------------|-----------|------|
| 특별시 / 광역시 / 특별자치시 | 구 (parts[1]) | 강남구, 해운대구 |
| 도 / 특별자치도 | 시·군 (parts[1], ~시/~군) | 안양시, 가평군 |

구현 위치: `mobile/lib/features/auth/screens/school_select_screen.dart` `_extractRegion()`, `backend/app/services/neis_service.py` `_extract_district()`

---

## 추가 작업 계획서 (플레이스토어 출시 전)

### 즉시 필요 (기능 완성)

| # | 상태 | 항목 | 위치 | 설명 |
|---|------|------|------|------|
| 1 | ✅ 완료 | 카카오 앱 키 등록 | `mobile/lib/core/constants.dart` | `95593f4d0972be3dd5072657262c5602` 적용 완료 |
| 2 | ✅ 완료 | AndroidManifest 카카오 스킴 | `mobile/android/app/src/main/AndroidManifest.xml` | 카카오 OAuth Activity + momstalk:// 딥링크 적용 완료 |
| 3 | ✅ 완료 | iOS Info.plist 카카오 스킴 | `mobile/ios/Runner/Info.plist` | `LSApplicationQueriesSchemes` + `CFBundleURLSchemes` 적용 완료 |
| 4 | ✅ 완료 | 초대 링크 딥링크 (app_links) | `mobile/lib/main.dart` | `AppLinks().uriLinkStream` 구독 → `/invite/{token}` 라우팅 구현 완료 |
| 5 | ✅ 완료 | board_screen 눈팅 뷰 접근 제어 | `mobile/lib/features/board/screens/board_screen.dart` | lurker는 school/grade 탭만 허용, region/free는 잠금 UI로 표시 |
| 6 | ✅ 완료 | 관리자 계정 초기 시드 | `admin/seed_admin.py` | `cd admin && python seed_admin.py` 실행 → 대화형 계정 생성 |
| 7 | ✅ 완료 | 토큰 저장소 플랫폼 분기 | `mobile/lib/core/api_client.dart` | kIsWeb: SharedPreferences(web) / FlutterSecureStorage(mobile) 분기 |
| 8 | ✅ 완료 | go_router 라우트 순서 수정 | `mobile/lib/core/router.dart` | `/board/write`를 `/board/:postId` 앞으로 이동 (FormatException 수정) |
| 9 | ✅ 완료 | 한글 폰트 Noto Sans KR 적용 | `mobile/lib/core/theme.dart`, `mobile/web/index.html` | google_fonts 패키지 + CSS 사전 로드로 두부문자 방지 |
| 10 | ✅ 완료 | 지역 표시 단위 수정 (도→시/군) | `school_select_screen.dart`, `neis_service.py` | 경기도 학교 → 안양시 등 시/군 단위 표시 |
| 11 | ✅ 완료 | SelectionArea 제거 | `mobile/lib/main.dart` | Overlay 의존성 충돌로 인한 크래시 수정 |
| 12 | ✅ 완료 | S3 캡처 이미지 즉시 삭제 | `backend/app/services/capture_service.py` | approve/reject 시 boto3로 S3 Object 동기 즉시 삭제 (Lifecycle 불필요) |
| 13 | ✅ 완료 | Android/iOS 플랫폼 추가 | `mobile/android/`, `mobile/ios/` | `flutter create --platforms=android,ios .` 실행 완료 |

#### Android 실기기 테스트 전 필수 설정

Android 플랫폼이 추가되었습니다. 카카오 로그인 실기기 테스트 전 아래를 완료하세요.

**1. 카카오 디벨로퍼스 → 앱 → 플랫폼 → Android에 키 해시 등록:**

```
디버그 키 해시 (현재 개발 PC): wO8RtdkqRfZA8jVnIWKkbd1yRdo=
```

다른 PC에서 개발 시 아래 명령으로 각 PC의 키 해시를 추출하세요:
```bash
keytool -exportcert -alias androiddebugkey \
  -keystore ~/.android/debug.keystore \
  -storepass android -keypass android \
  | openssl sha1 -binary | openssl base64
```

**2. 릴리즈 빌드 시 (Play Console 서명 키):**
```bash
keytool -exportcert -alias <your-release-alias> \
  -keystore <your-keystore.jks> | openssl sha1 -binary | openssl base64
```

**3. 에뮬레이터로 실행:**
```bash
cd mobile
flutter run -d emulator-5554   # 또는 연결된 기기 ID
```

#### iOS 실기기 테스트 (macOS 필요)

iOS 빌드는 macOS + Xcode가 있는 환경에서만 가능합니다. Info.plist는 기존 설정이 유지됩니다.

### 배포 전 (인프라)

| # | 항목 | 설명 |
|---|------|------|
| A | AWS Lightsail 인스턴스 생성 | 서울 리전, **최소 $12/월 (2GB RAM)** — 1GB는 Docker 구동 시 OOM 발생 |
| B | Swap 메모리 설정 | 서버 생성 직후 `fallocate -l 2G /swapfile` → fstab 등록 (DB 안정성) |
| C | Let's Encrypt 인증서 발급 | `certbot certonly --webroot -w /var/www/certbot -d api.momstalk.kr` |
| D | nginx.conf IP 화이트리스트 | `/admin/` location의 `allow` 라인에 관리자 IP 추가 후 `deny all` 활성화 |
| E | `.env` 프로덕션 값 설정 | `DEBUG=false`, `KAKAO_CLIENT_ID`, `AWS_*`, `FCM_SERVICE_ACCOUNT_JSON` |
| F | GitHub Actions CI | push → docker build → Lightsail SSH 배포 자동화 |

### Google Play 출시

| # | 항목 | 설명 |
|---|------|------|
| G | 개인정보처리방침 | Notion 퍼블릭 페이지 작성 → URL을 스토어 등록 시 제출 |
| H | 이용약관 | 동일 Notion 페이지 (별도 섹션 또는 별도 페이지) |
| I | 카카오 비즈앱 전환 | 전화번호 동의항목 사용 필수 조건 — 카카오 개발자 콘솔 신청 |
| J | Flutter 릴리즈 빌드 | `flutter build apk --release` / `flutter build appbundle` |
| K | 심사용 테스트 계정 준비 | 카카오 없이 앱 내부 진입 가능한 Dummy 계정 (심사 노트에 ID/PW 제공) |
| L | app-release.aab → Play Console | 내부 테스트 → 비공개 테스트 → 프로덕션 단계별 출시 |

### App Store 출시 (추후)

> Apple 등록은 현재 우선순위에서 제외. Google Play 안정화 후 진행.

| # | 항목 | 설명 |
|---|------|------|
| M | Sign in with Apple 구현 | App Store 심사 필수 (소셜 로그인 있으면 Apple 로그인 병행 의무) |
| N | iOS 릴리즈 빌드 | macOS + Xcode 필요, `flutter build ipa` |
| O | App Store Connect 등록 | TestFlight 내부 테스트 → 심사 제출 |

### MVP 이후 (운영 안정화 후)

| # | 항목 | 설명 |
|---|------|------|
| P | SSE → Redis Pub/Sub 전환 | 멀티 인스턴스 배포 시 필요 (현재 인메모리 큐) |
| Q | 관리자 대시보드 도메인 | `admin.momstalk.kr` 서브도메인 + HTTPS 적용 |
| R | 매너온도 시스템 | 좋아요/댓글 수 기반 manner_score 계산 로직 |
