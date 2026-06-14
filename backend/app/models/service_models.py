"""
서비스 DB 전용 모델 (DATABASE_URL 연결)
anon_id 외에는 신원 정보 일절 없음.
"""
from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import DeclarativeBase, relationship


class Base(DeclarativeBase):
    pass


class User(Base):
    """익명 유저. anon_id만 알며 전화번호 등 신원 정보는 없음."""
    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    anon_id = Column(String(64), unique=True, nullable=False, index=True)
    nickname = Column(String(30), nullable=True)        # 없으면 자동 생성 닉네임
    region = Column(String(30), nullable=True)          # 지역 (예: 강남구, 수원시)
    school_code = Column(String(20), nullable=False)
    school_name = Column(String(100), nullable=False)
    grade = Column(Integer, nullable=False)
    class_num = Column(Integer, nullable=True)
    school_type = Column(String(10), nullable=False)
    manner_score = Column(Integer, default=36)          # 블라인드 매너온도 유사
    is_banned = Column(Boolean, default=False)
    profile_updated_at = Column(DateTime, nullable=True)  # 프로필 최종 수정일 (월 1회 제한)
    created_at = Column(DateTime, default=datetime.utcnow)

    posts = relationship("Post", back_populates="author")
    comments = relationship("Comment", back_populates="author")


class Post(Base):
    __tablename__ = "posts"

    id = Column(Integer, primary_key=True)
    author_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    board_type = Column(String(20), nullable=False)     # grade / school / school_ask / region
    school_code = Column(String(20), nullable=False)
    grade = Column(Integer, nullable=True)              # class / grade 게시판에서만 사용
    class_num = Column(Integer, nullable=True)          # class 게시판에서만 사용
    title = Column(String(200), nullable=False)
    content = Column(Text, nullable=False)
    is_anonymous = Column(Boolean, default=True)
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
    reason = Column(String(200), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    __table_args__ = (
        __import__("sqlalchemy").UniqueConstraint("reporter_id", "target_type", "target_id", name="uq_report"),
    )
