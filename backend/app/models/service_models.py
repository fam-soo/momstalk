"""
통합 DB 모델 (DATABASE_URL 연결)
인증 테이블(PhoneVerification, ParentVerification) 포함.
"""
from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, LargeBinary, Numeric, SmallInteger, String, Text, JSON
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, relationship


class Base(DeclarativeBase):
    pass


# ── 인증 테이블 (구 Auth DB → 통합) ──────────────────────────

class PhoneVerification(Base):
    """SMS 인증 코드 임시 저장 (TTL 5분)"""
    __tablename__ = "phone_verifications"

    id = Column(Integer, primary_key=True)
    phone_number = Column(String(20), nullable=False, index=True)
    code = Column(String(6), nullable=False)
    is_used = Column(Boolean, default=False)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)


class ParentVerification(Base):
    """
    학부모 인증 레코드.
    anon_id = HMAC-SHA256(전화번호, ANON_HASH_SECRET) — 이 값으로 User와 연결.
    """
    __tablename__ = "parent_verifications"

    id = Column(Integer, primary_key=True)
    anon_id = Column(String(64), unique=True, nullable=False, index=True)
    school_code = Column(String(20), nullable=False)
    school_name = Column(String(100), nullable=False)
    grade = Column(Integer, nullable=False)
    class_num = Column(Integer, nullable=False)
    school_type = Column(String(10), nullable=False)
    verified_at = Column(DateTime, default=datetime.utcnow)
    is_active = Column(Boolean, default=True)


class UserChild(Base):
    """자녀 정보. 한 계정에 복수 등록 가능."""
    __tablename__ = "user_children"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    school_code = Column(String(20), nullable=True)
    school_name = Column(String(100), nullable=True)
    grade = Column(Integer, nullable=True)
    class_num = Column(Integer, nullable=True)
    school_type = Column(String(10), nullable=True)
    region = Column(String(50), nullable=True)
    # 학원 맞춤 추천용 — 아이 학습 성향 태그(["칭찬에_약해요", "외향적이에요"])와 현재 성적대
    student_traits = Column(JSONB, nullable=True)
    score_level = Column(String(20), nullable=True)
    # 가입 시 입력 — 학습 목표(복수 선택): ["선행", "심화", "내신", "수능", "경시", "영재"]
    learning_goals = Column(JSONB, nullable=True)
    # 과목별 선행 수준/성적 — {"수학": {"선행수준": "1학기 선행", "성적": "상"}, "영어": {...}}
    subject_levels = Column(JSONB, nullable=True)
    # 학원 추천받기 설문 3단계 — 숙제 허용치: "30분"|"60분"|"90분"|"120분"|"상관없음"
    homework_tolerance = Column(String(20), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class UserFcmToken(Base):
    """기기별 FCM 푸시 토큰. 한 계정이 여러 기기(모바일/PC 웹 등)에서 동시에
    알림을 받을 수 있도록 users.fcm_token(단일 컬럼, deprecated) 대신 사용."""
    __tablename__ = "user_fcm_tokens"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    token = Column(String(300), nullable=False, unique=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class Notification(Base):
    """알림함에 쌓이는 알림 이력. FCM 푸시는 기기가 꺼져있거나 알림 권한이
    없으면 놓치기 쉬워서, 앱 안에서 모아 볼 수 있는 목록을 별도로 남긴다.
    푸시 발송과 항상 함께 생성된다 (notification_service.notify_user 참고)."""
    __tablename__ = "notifications"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    type = Column(String(30), nullable=False)   # comment / dm / auth_approved / auth_rejected
    title = Column(String(200), nullable=False)
    body = Column(Text, nullable=True)
    data = Column(JSON, nullable=True)          # {"post_id": "123"} 등 클릭 시 이동에 필요한 정보
    is_read = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)


class NotificationPreference(Base):
    """알림 종류별 on/off. 게시판(지역/학교/학년/학원) 새 글 알림은 기본
    꺼짐(opt-in)이지만, 내 글에 달린 댓글 알림(notify_comment)은 기존부터
    항상 발송되던 기능이라 default=True(opt-out)로 둬 기존 사용자의 동작을
    바꾸지 않는다. 다자녀라도 자녀별로 나누지 않고 종류별 스위치 하나로 단순화."""
    __tablename__ = "notification_prefs"

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    notify_comment = Column(Boolean, default=True, nullable=False, server_default="true")
    notify_region = Column(Boolean, default=False, nullable=False, server_default="false")
    notify_school = Column(Boolean, default=False, nullable=False, server_default="false")
    notify_grade = Column(Boolean, default=False, nullable=False, server_default="false")
    notify_academy = Column(Boolean, default=False, nullable=False, server_default="false")
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class User(Base):
    """익명 유저. anon_id만 알며 전화번호 등 신원 정보는 없음."""
    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    anon_id = Column(String(64), unique=True, nullable=True, index=True)  # 관리자 계정은 null
    nickname = Column(String(30), nullable=True)
    region = Column(String(30), nullable=True)
    school_code = Column(String(20), nullable=True)      # deprecated — active_child 우선
    school_name = Column(String(100), nullable=True)     # deprecated
    grade = Column(Integer, nullable=True)               # deprecated
    class_num = Column(Integer, nullable=True)           # deprecated
    school_type = Column(String(10), nullable=True)      # deprecated
    manner_score = Column(Integer, default=365, server_default="365")
    fcm_token = Column(String(256), nullable=True)  # deprecated — user_fcm_tokens 테이블 사용 (기기별 다중 토큰)
    is_banned = Column(Boolean, default=False)
    is_admin = Column(Boolean, default=False)
    suspended_until = Column(DateTime, nullable=True)
    warning_count = Column(Integer, default=0)
    certified_nickname = Column(String(50), nullable=True)
    school_short_name = Column(String(20), nullable=True)
    # v3 인증 관련
    social_provider = Column(String(20), nullable=True)
    member_grade = Column(String(10), nullable=False, server_default="lurker")  # lurker / member / admin
    auth_route = Column(String(10), nullable=True)
    auth_pending = Column(Boolean, default=False)
    profile_updated_at = Column(DateTime, nullable=True)
    # 카카오 로그인 유저 식별자 (anon_id의 역추적 방지를 위해 별도 저장)
    kakao_id = Column(String(30), nullable=True, index=True)
    # 자녀 추가·인증 캡처 심사 면제 권한 (관리자 부여)
    is_trusted = Column(Boolean, default=False, server_default="false")
    # 관리자 전용 자격증명 (일반 유저는 null)
    admin_username = Column(String(50), unique=True, nullable=True)
    admin_password_hash = Column(String(128), nullable=True)
    # 다자녀 지원
    active_child_id = Column(Integer, ForeignKey("user_children.id", ondelete="SET NULL"), nullable=True)
    academy_review_count = Column(Integer, default=0, server_default="0")
    # 관리자 화면용 접속 통계 (카카오 로그인 성공 시마다 갱신)
    last_login_at = Column(DateTime, nullable=True)
    login_count = Column(Integer, default=0, server_default="0")
    created_at = Column(DateTime, default=datetime.utcnow)

    posts = relationship("Post", back_populates="author")
    comments = relationship("Comment", back_populates="author")
    children = relationship(
        "UserChild",
        foreign_keys="UserChild.user_id",
        primaryjoin="User.id == UserChild.user_id",
        lazy="selectin",
    )
    active_child = relationship(
        "UserChild",
        foreign_keys=[active_child_id],
        primaryjoin="User.active_child_id == UserChild.id",
        lazy="joined",
    )


class Post(Base):
    __tablename__ = "posts"

    id = Column(Integer, primary_key=True)
    author_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    board_type = Column(String(20), nullable=False)     # grade / school / free / region / notice
    mention_tags = Column(JSON, nullable=True)           # free 게시판 @태그 ["region:기장군", "school:B100", "grade:1"]
    school_code = Column(String(20), nullable=True)      # 일반 게시글은 항상 값 있음. 공지사항만 NULL 가능(지역/전체 타겟)
    target_region = Column(String(50), nullable=True)    # 공지사항 지역 타겟 (school_code 미지정 시). 일반 게시글은 미사용
    grade = Column(Integer, nullable=True)              # class / grade 게시판에서만 사용
    class_num = Column(Integer, nullable=True)          # class 게시판에서만 사용
    title = Column(String(200), nullable=False)
    content = Column(Text, nullable=False)
    is_anonymous = Column(Boolean, default=True)
    nickname_type = Column(String(10), nullable=False, server_default="anon")  # anon / certified
    # 작성 시점 닉네임 스냅샷 — 이후 유저가 닉네임을 바꿔도 과거 글의 표시명은
    # 바뀌지 않도록 고정한다. NULL이면(과거 데이터) 조회 시 현재 닉네임으로 대체.
    nickname_snapshot = Column(String(50), nullable=True)
    view_count = Column(Integer, default=0)
    like_count = Column(Integer, default=0)
    scrap_count = Column(Integer, default=0)
    report_count = Column(Integer, default=0)
    is_hidden = Column(Boolean, default=False)          # 신고 누적 시 자동 블라인드
    is_deleted = Column(Boolean, default=False)         # soft delete
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    author = relationship("User", back_populates="posts")
    comments = relationship("Comment", back_populates="post")


class Comment(Base):
    __tablename__ = "comments"

    id = Column(Integer, primary_key=True)
    post_id = Column(Integer, ForeignKey("posts.id"), nullable=False)
    author_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    parent_id = Column(Integer, ForeignKey("comments.id"), nullable=True)  # 대댓글
    content = Column(Text, nullable=False)
    is_anonymous = Column(Boolean, default=True)
    nickname_type = Column(String(10), nullable=False, server_default="anon")  # anon / certified
    # 작성 시점 닉네임 스냅샷 — Post.nickname_snapshot과 동일한 목적.
    nickname_snapshot = Column(String(50), nullable=True)
    like_count = Column(Integer, default=0)
    report_count = Column(Integer, default=0)
    is_hidden = Column(Boolean, default=False)
    is_deleted = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    post = relationship("Post", back_populates="comments")
    author = relationship("User", back_populates="comments")


class Like(Base):
    __tablename__ = "likes"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    target_type = Column(String(10), nullable=False)    # post / comment
    target_id = Column(Integer, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    __table_args__ = (
        __import__("sqlalchemy").UniqueConstraint("user_id", "target_type", "target_id", name="uq_like"),
    )


class Scrap(Base):
    __tablename__ = "scraps"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    post_id = Column(Integer, ForeignKey("posts.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    __table_args__ = (
        __import__("sqlalchemy").UniqueConstraint("user_id", "post_id", name="uq_scrap"),
    )


class Report(Base):
    __tablename__ = "reports"

    id = Column(Integer, primary_key=True)
    reporter_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    target_type = Column(String(10), nullable=False)    # post / comment
    target_id = Column(Integer, nullable=False)
    category = Column(String(20), nullable=False, default="OTHER")  # SPAM/OBSCENE/ABUSE/PERSONAL_INFO/MISINFORMATION/ILLEGAL/OFF_TOPIC/OTHER
    reason = Column(String(200), nullable=False)        # detail_reason (기타 사유 직접 입력)
    status = Column(String(20), default="pending")      # pending / reviewed / dismissed / actioned
    reviewed_by = Column(Integer, nullable=True)        # 관리자 user_id
    reviewed_at = Column(DateTime, nullable=True)
    action_taken = Column(String(50), nullable=True)    # warned / suspended_7d / suspended_30d / banned / cleared
    created_at = Column(DateTime, default=datetime.utcnow)

    __table_args__ = (
        __import__("sqlalchemy").UniqueConstraint("reporter_id", "target_type", "target_id", name="uq_report"),
    )


class UserWarning(Base):
    """관리자 또는 자동화에 의한 경고/정지 이력."""
    __tablename__ = "user_warnings"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    reason = Column(Text, nullable=False)
    warning_type = Column(String(20), nullable=False)   # warning / suspend_7d / suspend_30d / banned
    issued_by = Column(Integer, nullable=True)          # 관리자 id (NULL이면 자동)
    expires_at = Column(DateTime, nullable=True)        # 정지 해제 시각 (NULL이면 영구)
    created_at = Column(DateTime, default=datetime.utcnow)


class Block(Base):
    """특정 유저의 게시글/댓글 전부 숨기기."""
    __tablename__ = "blocks"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    blocked_user_id = Column(Integer, nullable=False)   # 차단 대상 service user id
    created_at = Column(DateTime, default=datetime.utcnow)

    __table_args__ = (
        __import__("sqlalchemy").UniqueConstraint("user_id", "blocked_user_id", name="uq_block"),
    )


class Conversation(Base):
    """1:1 대화방. user_a_id < user_b_id 항상 유지."""
    __tablename__ = "conversations"

    id = Column(Integer, primary_key=True)
    user_a_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    user_b_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    last_message_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    messages = relationship("DirectMessage", back_populates="conversation", lazy="dynamic")

    __table_args__ = (
        __import__("sqlalchemy").UniqueConstraint("user_a_id", "user_b_id", name="uq_conversation"),
    )


class DirectMessage(Base):
    __tablename__ = "direct_messages"

    id = Column(Integer, primary_key=True)
    conversation_id = Column(Integer, ForeignKey("conversations.id"), nullable=False)
    sender_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    content = Column(Text, nullable=False)
    is_read = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    conversation = relationship("Conversation", back_populates="messages")


class AuthCapture(Base):
    """알림장 캡처 업로드 — 관리자 대조 승인용."""
    __tablename__ = "auth_captures"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    capture_type = Column(String(20), server_default="initial", nullable=False)  # initial / child_add
    s3_key = Column(String(300), nullable=True)   # 구 Supabase Storage 키 (레거시 행 하위호환용, 신규 행은 미사용)
    image_data = Column(LargeBinary, nullable=True)       # 캡처 이미지 원본 (심사 후 삭제)
    image_content_type = Column(String(30), nullable=True)
    input_school_code = Column(String(20), nullable=False)
    input_school_name = Column(String(100), nullable=False)
    input_grade = Column(Integer, nullable=False)
    input_class_num = Column(Integer, nullable=True)
    input_school_type = Column(String(20), nullable=True)
    input_region = Column(String(50), nullable=True)
    status = Column(String(20), default="pending")       # pending / approved / rejected
    reviewed_by = Column(Integer, nullable=True)
    reviewed_at = Column(DateTime, nullable=True)
    reject_reason = Column(String(200), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class InviteLink(Base):
    """정회원이 발급하는 추천 링크.

    카카오톡 단체 채팅방 등 한 링크를 여러 명에게 동시에 공유하는 경우가
    많아 1회 소모성이 아니라 정원제로 바꿨다(기본 24시간 · 최대 10명).
    used_by/used_at은 "가장 최근 사용자" 표시용으로 남겨두고, 실제 사용
    인원 집계와 중복 참여 방지는 InviteLinkUse로 한다."""
    __tablename__ = "invite_links"

    id = Column(Integer, primary_key=True)
    token = Column(String(64), unique=True, nullable=False, index=True)
    issuer_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    school_code = Column(String(20), nullable=False)     # 발급자의 school_code 고정
    school_name = Column(String(100), nullable=False)
    school_type = Column(String(10), nullable=False)
    used_by = Column(Integer, ForeignKey("users.id"), nullable=True)  # 가장 최근 사용자 (표시용)
    used_at = Column(DateTime, nullable=True)
    max_uses = Column(Integer, nullable=False, server_default="10")
    use_count = Column(Integer, nullable=False, server_default="0")
    expires_at = Column(DateTime, nullable=False)        # 발급 후 24시간
    created_at = Column(DateTime, default=datetime.utcnow)


class InviteLinkUse(Base):
    """초대 링크의 실제 사용 이력 — 정원 집계 + 같은 유저 중복 참여 방지용."""
    __tablename__ = "invite_link_uses"

    id = Column(Integer, primary_key=True)
    invite_link_id = Column(Integer, ForeignKey("invite_links.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    used_at = Column(DateTime, default=datetime.utcnow)

    __table_args__ = (
        __import__("sqlalchemy").UniqueConstraint("invite_link_id", "user_id", name="uq_invite_link_use"),
    )


class AdminUser(Base):
    """관리자 계정 (별도 자격증명, service User와 무관)."""
    __tablename__ = "admin_users"

    id = Column(Integer, primary_key=True)
    username = Column(String(50), unique=True, nullable=False)
    hashed_password = Column(String(200), nullable=False)
    role = Column(String(20), default="moderator")       # superadmin / moderator
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class ProfanityWord(Base):
    """DB 기반 금칙어 관리 (관리자 대시보드에서 실시간 추가/삭제)."""
    __tablename__ = "profanity_words"

    id = Column(Integer, primary_key=True)
    word = Column(String(100), unique=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)


class AdminAction(Base):
    """관리자 행동 이력 (감사 로그)."""
    __tablename__ = "admin_actions"

    id = Column(Integer, primary_key=True)
    admin_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    action_type = Column(String(50), nullable=False)     # approve_capture / reject_capture / ban_user / ...
    target_type = Column(String(20), nullable=True)      # user / post / comment / capture
    target_id = Column(Integer, nullable=True)
    detail = Column(Text, nullable=True)                 # JSON 직렬화 사유/파라미터
    created_at = Column(DateTime, default=datetime.utcnow)


class School(Base):
    """NEIS 연동 학교 정보 (전국 캐시)."""
    __tablename__ = "schools"

    id = Column(Integer, primary_key=True)
    school_code = Column(String(20), unique=True, nullable=False, index=True)
    school_name = Column(String(100), nullable=False, index=True)
    school_type = Column(String(10), nullable=False)   # elementary/middle/high
    address = Column(String(200), nullable=True)
    region = Column(String(50), nullable=True, index=True)  # 구/군 단위
    updated_at = Column(DateTime, default=datetime.utcnow)


class Academy(Base):
    """NEIS 연동 학원 정보."""
    __tablename__ = "academies"

    id = Column(Integer, primary_key=True)
    neis_academy_code = Column(String(30), unique=True, nullable=True)
    name = Column(String(100), nullable=False, index=True)
    region = Column(String(50), nullable=True, index=True)
    address = Column(String(200), nullable=True)
    phone = Column(String(20), nullable=True)
    subjects = Column(JSONB, nullable=True)              # ["수학", "영어"]
    school_type = Column(String(20), nullable=True)
    is_b2b = Column(Boolean, default=False)
    b2b_expires_at = Column(DateTime, nullable=True)
    review_count = Column(Integer, default=0)
    avg_rating = Column(Numeric(3, 2), nullable=True)
    # 강남엄마 스크래핑(scripts/scrape_gangmom.py, 리뷰 제외)으로 보강 — 수업당 평균 정원(명).
    # 대/중/소 같은 버킷 라벨은 저장하지 않고 조회 시점에 이 숫자로부터 계산한다
    # (기준을 나중에 바꿔도 재수집 없이 라벨링만 다시 하면 되도록).
    avg_class_capacity = Column(Numeric(5, 1), nullable=True)
    avg_tuition_10k_won = Column(Numeric(6, 1), nullable=True)  # 학원비 평균(만원)
    founded_year = Column(Integer, nullable=True)
    business_hours = Column(String(200), nullable=True)
    shuttle_bus = Column(Boolean, nullable=True)
    # 커리큘럼 방향(복수): ["선행", "심화", "내신", "수능", "경시", "영재"]
    # 수업 스타일(복수): ["강의형", "질문형", "토론형", "소수정예", "레벨테스트", "수준별", "온라인강의", "자체교재"]
    # 오늘학교(scripts/scrape_onaul.py)의 "수업 및 반편성 정보"에서 매핑되어 채워짐.
    curriculum_focus = Column(JSONB, nullable=True)
    class_style = Column(JSONB, nullable=True)
    # 시설(복수, 오늘학교 "시설 및 편의사항"에서 채워짐 — 변별력 낮은 항목은 제외):
    # ["자습실 제공", "설명회 진행", "스터디 모임 있음"] (셔틀버스는 shuttle_bus로 별도 저장)
    facilities = Column(JSONB, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class AcademyReview(Base):
    """학원 후기 (구조화 평가 + 자유 텍스트)."""
    __tablename__ = "academy_reviews"

    id = Column(Integer, primary_key=True)
    academy_id = Column(Integer, ForeignKey("academies.id", ondelete="CASCADE"), nullable=False, index=True)
    author_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    subjects = Column(JSONB, nullable=True)       # ["수학", "영어"]
    teacher_styles = Column(JSONB, nullable=True)  # ["꼼꼼해요", "친절해요"]
    homework_level = Column(String(20), nullable=True)
    score_improvement = Column(String(30), nullable=True)
    # 학원 맞춤 추천용 — 후기 작성 시점 기준 수강생 성향/성적대
    student_traits = Column(JSONB, nullable=True)
    score_level = Column(String(20), nullable=True)
    # 선생님 피드백 주기: "일간"|"주간"|"월간"|"분기"|"반기"
    feedback_frequency = Column(String(20), nullable=True)
    # 다니기 전/후 진도·성적 변화 — {"before": "...", "after": "..."}
    score_change = Column(JSONB, nullable=True)
    # 비슷한 성향의 아이에게 추천하는지 (추천/비추천)
    recommend_to_similar = Column(Boolean, nullable=True)
    review_text = Column(Text, nullable=False)
    rating = Column(SmallInteger, nullable=False)
    nickname_type = Column(String(10), nullable=False, server_default="anon")
    # 작성 시점 닉네임 스냅샷 — Post.nickname_snapshot과 동일한 목적.
    nickname_snapshot = Column(String(50), nullable=True)
    is_anonymous = Column(Boolean, nullable=False, default=True)
    report_count = Column(Integer, default=0)
    is_hidden = Column(Boolean, default=False)
    is_seed = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)


class AcademyReviewUnlock(Base):
    """사용자가 후기를 가림 처리 없이 전체 열람할 수 있도록 허용된 학원 기록.

    후기 열람 쿼터는 "학원 개수" 단위로 소비된다 — 한 번 열람 허용(해금)된
    학원은 계속 유지되며, 해금 가능한 학원 수는 사용자가 작성한 후기 수에
    따라 늘어난다 (academy_service._academy_unlock_quota 참고).
    """
    __tablename__ = "academy_review_unlocks"
    __table_args__ = (
        __import__("sqlalchemy").UniqueConstraint("user_id", "academy_id", name="uq_academy_review_unlock"),
    )

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    academy_id = Column(Integer, ForeignKey("academies.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
