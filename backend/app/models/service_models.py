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
    created_at = Column(DateTime, default=datetime.utcnow)


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
    fcm_token = Column(String(256), nullable=True)
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
    board_type = Column(String(20), nullable=False)     # grade / school / free / region
    mention_tags = Column(JSON, nullable=True)           # free 게시판 @태그 ["region:기장군", "school:B100", "grade:1"]
    school_code = Column(String(20), nullable=False)
    grade = Column(Integer, nullable=True)              # class / grade 게시판에서만 사용
    class_num = Column(Integer, nullable=True)          # class 게시판에서만 사용
    title = Column(String(200), nullable=False)
    content = Column(Text, nullable=False)
    is_anonymous = Column(Boolean, default=True)
    nickname_type = Column(String(10), nullable=False, server_default="anon")  # anon / certified
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
    """정회원이 발급하는 추천 링크."""
    __tablename__ = "invite_links"

    id = Column(Integer, primary_key=True)
    token = Column(String(64), unique=True, nullable=False, index=True)
    issuer_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    school_code = Column(String(20), nullable=False)     # 발급자의 school_code 고정
    school_name = Column(String(100), nullable=False)
    school_type = Column(String(10), nullable=False)
    used_by = Column(Integer, ForeignKey("users.id"), nullable=True)
    used_at = Column(DateTime, nullable=True)
    expires_at = Column(DateTime, nullable=False)        # 발급 후 48시간
    created_at = Column(DateTime, default=datetime.utcnow)


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
    review_text = Column(Text, nullable=False)
    rating = Column(SmallInteger, nullable=False)
    nickname_type = Column(String(10), nullable=False, server_default="anon")
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
