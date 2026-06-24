"""
MomsTalk 관리자 대시보드 — Streamlit

실행:
  cd admin && streamlit run app.py --server.port 8501

Nginx IP 화이트리스트 예시 (nginx.conf):
  location /admin/ {
      allow 1.2.3.4;   # 관리자 IP
      deny  all;
      proxy_pass http://admin:8501/;
  }
"""
import os
import datetime
from dotenv import load_dotenv

import streamlit as st
import pandas as pd
from sqlalchemy import text

from db import SessionLocal
import s3_helper

load_dotenv()

# ── 패스워드 게이트 ─────────────────────────────────────────────────

ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "changeme")


def _check_password() -> bool:
    if st.session_state.get("authenticated"):
        return True
    pwd = st.text_input("관리자 비밀번호", type="password", key="login_pw")
    if st.button("로그인"):
        if pwd == ADMIN_PASSWORD:
            st.session_state["authenticated"] = True
            st.rerun()
        else:
            st.error("비밀번호가 틀렸습니다.")
    return False


# ── 공통 DB 헬퍼 ────────────────────────────────────────────────────

def _db():
    return SessionLocal()


# ── 사이드바 네비게이션 ──────────────────────────────────────────────

def _sidebar():
    st.sidebar.title("🏠 MomsTalk 관리자")
    st.sidebar.markdown("---")
    pages = {
        "📋 캡처 심사": "captures",
        "🚨 신고 처리": "reports",
        "👥 유저 관리": "users",
        "📊 대시보드": "dashboard",
    }
    selected = st.sidebar.radio("메뉴", list(pages.keys()))
    st.sidebar.markdown("---")
    if st.sidebar.button("로그아웃"):
        st.session_state["authenticated"] = False
        st.rerun()
    return pages[selected]


# ══════════════════════════════════════════════════════════════════
# 페이지 1 — 캡처 심사
# ══════════════════════════════════════════════════════════════════

def page_captures():
    st.title("📋 알림장 캡처 심사")

    tab_pending, tab_done = st.tabs(["대기 중", "처리 완료"])

    with tab_pending:
        with _db() as db:
            rows = db.execute(text("""
                SELECT ac.id, ac.user_id, u.nickname, ac.input_school_name,
                       ac.input_grade, ac.input_class_num, ac.s3_key, ac.created_at
                FROM auth_captures ac
                JOIN users u ON u.id = ac.user_id
                WHERE ac.status = 'pending'
                ORDER BY ac.created_at ASC
            """)).fetchall()

        if not rows:
            st.info("처리할 캡처가 없습니다.")
            return

        st.markdown(f"**총 {len(rows)}건** 대기 중")

        for row in rows:
            with st.expander(
                f"[#{row.id}] {row.nickname} — {row.input_school_name} {row.input_grade}학년"
                + (f" {row.input_class_num}반" if row.input_class_num else ""),
                expanded=True,
            ):
                col_img, col_info = st.columns([1, 1])

                with col_info:
                    st.markdown(f"""
                    | 항목 | 값 |
                    |------|-----|
                    | 캡처 ID | `{row.id}` |
                    | 유저 ID | `{row.user_id}` |
                    | 닉네임 | {row.nickname} |
                    | 입력 학교 | {row.input_school_name} |
                    | 입력 학년/반 | {row.input_grade}학년 {row.input_class_num or '-'}반 |
                    | 제출 시각 | {row.created_at.strftime('%Y-%m-%d %H:%M') if row.created_at else '-'} |
                    """)

                with col_img:
                    url = s3_helper.get_presigned_url(row.s3_key)
                    if url:
                        st.image(url, caption="알림장 캡처", use_container_width=True)
                    else:
                        st.warning("이미지 URL 생성 실패 (AWS 미설정 또는 키 오류)")
                        st.code(row.s3_key, language="text")

                col_approve, col_reject = st.columns(2)
                with col_approve:
                    if st.button("✅ 승인", key=f"approve_{row.id}", type="primary"):
                        _approve_capture(row.id, row.user_id, row.input_school_name,
                                         row.input_school_code if hasattr(row, 'input_school_code') else '',
                                         row.input_grade, row.input_class_num, row.s3_key)
                        st.rerun()

                with col_reject:
                    reject_reason = st.text_input("거절 사유", key=f"reason_{row.id}", placeholder="필수 입력")
                    if st.button("❌ 거절", key=f"reject_{row.id}"):
                        if not reject_reason.strip():
                            st.error("거절 사유를 입력해주세요.")
                        else:
                            _reject_capture(row.id, row.user_id, reject_reason, row.s3_key)
                            st.rerun()

    with tab_done:
        with _db() as db:
            rows = db.execute(text("""
                SELECT ac.id, ac.user_id, u.nickname, ac.input_school_name,
                       ac.input_grade, ac.status, ac.reviewed_at, ac.reject_reason
                FROM auth_captures ac
                JOIN users u ON u.id = ac.user_id
                WHERE ac.status != 'pending'
                ORDER BY ac.reviewed_at DESC
                LIMIT 50
            """)).fetchall()

        if rows:
            df = pd.DataFrame(rows, columns=["ID", "유저ID", "닉네임", "학교", "학년", "상태", "처리시각", "거절사유"])
            df["상태"] = df["상태"].map({"approved": "✅ 승인", "rejected": "❌ 거절"})
            st.dataframe(df, use_container_width=True, hide_index=True)


def _approve_capture(capture_id, user_id, school_name, school_code, grade, class_num, s3_key):
    with _db() as db:
        db.execute(text("""
            UPDATE auth_captures
            SET status='approved', reviewed_at=NOW()
            WHERE id=:id
        """), {"id": capture_id})
        db.execute(text("""
            UPDATE users
            SET member_grade='member', auth_pending=false,
                school_name=:school_name, grade=:grade,
                class_num=:class_num
            WHERE id=:user_id
        """), {"school_name": school_name, "grade": grade,
               "class_num": class_num, "user_id": user_id})
        db.commit()
    s3_helper.delete_object(s3_key)
    st.success(f"캡처 #{capture_id} 승인 완료")


def _reject_capture(capture_id, user_id, reason, s3_key):
    with _db() as db:
        db.execute(text("""
            UPDATE auth_captures
            SET status='rejected', reviewed_at=NOW(), reject_reason=:reason
            WHERE id=:id
        """), {"id": capture_id, "reason": reason})
        db.execute(text("""
            UPDATE users SET auth_pending=false WHERE id=:user_id
        """), {"user_id": user_id})
        db.commit()
    s3_helper.delete_object(s3_key)
    st.success(f"캡처 #{capture_id} 거절 처리 완료")


# ══════════════════════════════════════════════════════════════════
# 페이지 2 — 신고 처리
# ══════════════════════════════════════════════════════════════════

CATEGORY_LABELS = {
    "SPAM": "스팸/홍보", "OBSCENE": "음란/선정적", "ABUSE": "욕설/비방/혐오",
    "PERSONAL_INFO": "개인정보 노출", "MISINFORMATION": "허위사실", "ILLEGAL": "불법정보",
    "OFF_TOPIC": "주제 무관", "OTHER": "기타",
}


def _get_content_preview(db, target_type, target_id):
    if target_type == "post":
        row = db.execute(text("SELECT title, content FROM posts WHERE id=:id"), {"id": target_id}).fetchone()
        if row:
            return f"**[제목]** {row.title}\n\n**[내용]** {row.content[:300]}"
    elif target_type == "comment":
        row = db.execute(text("SELECT content FROM comments WHERE id=:id"), {"id": target_id}).fetchone()
        if row:
            return row.content[:300]
    return None


def page_reports():
    st.title("🚨 신고 처리")

    tab_pending, tab_done = st.tabs(["미처리", "처리 완료"])

    with tab_pending:
        with _db() as db:
            rows = db.execute(text("""
                SELECT r.id, r.reporter_id, r.target_type, r.target_id,
                       r.category, r.reason, r.status, r.created_at
                FROM reports r
                WHERE r.status = 'pending'
                ORDER BY r.created_at ASC
                LIMIT 100
            """)).fetchall()
            previews = {
                row.id: _get_content_preview(db, row.target_type, row.target_id)
                for row in rows
            }

        if not rows:
            st.info("처리할 신고가 없습니다.")
        else:
            st.markdown(f"**미처리 신고 {len(rows)}건**")

            for row in rows:
                cat = CATEGORY_LABELS.get(row.category, row.category)
                with st.expander(
                    f"[#{row.id}] {cat} — {row.target_type} #{row.target_id} "
                    f"({row.created_at.strftime('%m/%d %H:%M') if row.created_at else ''})"
                ):
                    st.markdown(f"""
                    - **신고자 ID**: {row.reporter_id}
                    - **대상**: {row.target_type} #{row.target_id}
                    - **카테고리**: {cat}
                    - **신고 사유**: {row.reason or '(없음)'}
                    """)

                    preview = previews.get(row.id)
                    if preview:
                        st.markdown("**▼ 신고된 콘텐츠**")
                        st.info(preview)

                    col1, col2, col3, col4, col5 = st.columns(5)
                    with col1:
                        if st.button("경고", key=f"warn_{row.id}"):
                            _review_report(row.id, row.target_type, row.target_id, "warn")
                            st.rerun()
                    with col2:
                        if st.button("7일 정지", key=f"sus7_{row.id}"):
                            _review_report(row.id, row.target_type, row.target_id, "suspend_7d")
                            st.rerun()
                    with col3:
                        if st.button("30일 정지", key=f"sus30_{row.id}"):
                            _review_report(row.id, row.target_type, row.target_id, "suspend_30d")
                            st.rerun()
                    with col4:
                        if st.button("영구 차단", key=f"ban_{row.id}", type="secondary"):
                            _review_report(row.id, row.target_type, row.target_id, "ban")
                            st.rerun()
                    with col5:
                        if st.button("기각", key=f"clear_{row.id}"):
                            _review_report(row.id, row.target_type, row.target_id, "cleared")
                            st.rerun()

    with tab_done:
        with _db() as db:
            rows = db.execute(text("""
                SELECT id, target_type, target_id, category, action_taken, reviewed_at
                FROM reports
                WHERE status != 'pending'
                ORDER BY reviewed_at DESC
                LIMIT 50
            """)).fetchall()
        if rows:
            df = pd.DataFrame(rows, columns=["ID", "대상유형", "대상ID", "카테고리", "처리결과", "처리시각"])
            df["카테고리"] = df["카테고리"].map(lambda c: CATEGORY_LABELS.get(c, c))
            st.dataframe(df, use_container_width=True, hide_index=True)
        else:
            st.info("처리 완료된 신고 없음")


def _review_report(report_id, target_type, target_id, action):
    with _db() as db:
        report_status = "dismissed" if action == "cleared" else "actioned"
        db.execute(text("""
            UPDATE reports
            SET status=:status, reviewed_at=NOW(), action_taken=:action
            WHERE id=:id
        """), {"id": report_id, "status": report_status, "action": action})

        # 신고 대상 콘텐츠 블라인드 + 작성자 조회
        author_id = None
        if action != "cleared":
            if target_type == "post":
                row = db.execute(text("SELECT author_id FROM posts WHERE id=:id"), {"id": target_id}).fetchone()
                if row:
                    author_id = row.author_id
                    db.execute(text("UPDATE posts SET is_hidden=true WHERE id=:id"), {"id": target_id})
            elif target_type == "comment":
                row = db.execute(text("SELECT author_id FROM comments WHERE id=:id"), {"id": target_id}).fetchone()
                if row:
                    author_id = row.author_id
                    db.execute(text("UPDATE comments SET is_hidden=true WHERE id=:id"), {"id": target_id})

        # 작성자 제재
        if author_id and action != "cleared":
            if action == "warn":
                db.execute(text("UPDATE users SET warning_count = warning_count + 1 WHERE id=:id"), {"id": author_id})
            elif action == "suspend_7d":
                db.execute(text("""
                    UPDATE users SET suspended_until = NOW() + INTERVAL '7 days',
                    warning_count = warning_count + 1 WHERE id=:id
                """), {"id": author_id})
            elif action == "suspend_30d":
                db.execute(text("""
                    UPDATE users SET suspended_until = NOW() + INTERVAL '30 days',
                    warning_count = warning_count + 1 WHERE id=:id
                """), {"id": author_id})
            elif action == "ban":
                db.execute(text("UPDATE users SET is_banned=true WHERE id=:id"), {"id": author_id})

        db.commit()
    st.success(f"신고 #{report_id} → {action}")


# ══════════════════════════════════════════════════════════════════
# 페이지 3 — 유저 관리
# ══════════════════════════════════════════════════════════════════

def page_users():
    st.title("👥 유저 관리")

    search = st.text_input("닉네임 또는 ID 검색", placeholder="예: 용감한학부모1234")

    with _db() as db:
        if search.strip():
            condition = "WHERE u.nickname ILIKE :q OR u.id::text = :q"
            rows = db.execute(text(f"""
                SELECT u.id, u.nickname, u.school_name, u.grade,
                       u.member_grade, u.auth_pending, u.is_banned,
                       u.suspended_until, u.warning_count, u.created_at
                FROM users u
                {condition}
                ORDER BY u.created_at DESC
                LIMIT 50
            """), {"q": f"%{search}%"}).fetchall()
        else:
            rows = db.execute(text("""
                SELECT u.id, u.nickname, u.school_name, u.grade,
                       u.member_grade, u.auth_pending, u.is_banned,
                       u.suspended_until, u.warning_count, u.created_at
                FROM users u
                ORDER BY u.created_at DESC
                LIMIT 100
            """)).fetchall()

    if not rows:
        st.info("유저가 없습니다.")
        return

    for row in rows:
        grade_badge = "🟢 정회원" if row.member_grade == "member" else ("⏳ 심사중" if row.auth_pending else "⚪ 눈팅")
        ban_badge = " 🔴 영구차단" if row.is_banned else ""
        suspend_badge = (
            f" ⛔ {row.suspended_until.strftime('%Y-%m-%d')}까지 정지"
            if row.suspended_until and row.suspended_until > datetime.datetime.utcnow()
            else ""
        )

        with st.expander(
            f"[#{row.id}] {row.nickname}  {grade_badge}{ban_badge}{suspend_badge}"
        ):
            col_info, col_actions = st.columns([2, 1])

            with col_info:
                st.markdown(f"""
                | | |
                |---|---|
                | 학교 | {row.school_name} {row.grade}학년 |
                | 가입 등급 | {grade_badge} |
                | 경고 횟수 | {row.warning_count}회 |
                | 가입일 | {row.created_at.strftime('%Y-%m-%d') if row.created_at else '-'} |
                """)

            with col_actions:
                days = st.selectbox("정지 기간", [3, 7, 14, 30], key=f"days_{row.id}")
                if st.button(f"{days}일 정지", key=f"suspend_{row.id}"):
                    _suspend_user(row.id, days)
                    st.rerun()
                if st.button("영구 차단", key=f"ban_{row.id}", type="secondary"):
                    _ban_user(row.id)
                    st.rerun()
                if row.is_banned:
                    if st.button("차단 해제", key=f"unban_{row.id}"):
                        _unban_user(row.id)
                        st.rerun()


def _suspend_user(user_id, days):
    with _db() as db:
        db.execute(text("""
            UPDATE users
            SET suspended_until = NOW() + :interval::interval,
                warning_count = warning_count + 1
            WHERE id = :user_id
        """), {"interval": f"{days} days", "user_id": user_id})
        db.commit()
    st.success(f"유저 #{user_id} → {days}일 정지")


def _ban_user(user_id):
    with _db() as db:
        db.execute(text("UPDATE users SET is_banned=true WHERE id=:id"), {"id": user_id})
        db.commit()
    st.success(f"유저 #{user_id} 영구 차단")


def _unban_user(user_id):
    with _db() as db:
        db.execute(text("UPDATE users SET is_banned=false WHERE id=:id"), {"id": user_id})
        db.commit()
    st.success(f"유저 #{user_id} 차단 해제")


# ══════════════════════════════════════════════════════════════════
# 페이지 4 — 대시보드 (통계)
# ══════════════════════════════════════════════════════════════════

def page_dashboard():
    st.title("📊 대시보드")

    with _db() as db:
        stats = db.execute(text("""
            SELECT
                (SELECT COUNT(*) FROM users) AS total_users,
                (SELECT COUNT(*) FROM users WHERE member_grade='member') AS members,
                (SELECT COUNT(*) FROM users WHERE auth_pending=true) AS pending,
                (SELECT COUNT(*) FROM posts WHERE is_deleted=false) AS posts,
                (SELECT COUNT(*) FROM reports WHERE status='pending') AS open_reports,
                (SELECT COUNT(*) FROM auth_captures WHERE status='pending') AS pending_captures
        """)).fetchone()

    col1, col2, col3 = st.columns(3)
    col1.metric("전체 유저", stats.total_users)
    col2.metric("정회원", stats.members)
    col3.metric("심사 대기", stats.pending_captures, delta=f"+{stats.pending} 보류" if stats.pending else None)

    col4, col5, col6 = st.columns(3)
    col4.metric("게시글 수", stats.posts)
    col5.metric("미처리 신고", stats.open_reports)
    col6.metric("심사 대기 캡처", stats.pending_captures)

    st.markdown("---")
    st.subheader("최근 7일 가입 추이")

    with _db() as db:
        signup_rows = db.execute(text("""
            SELECT DATE(created_at) AS day, COUNT(*) AS cnt
            FROM users
            WHERE created_at >= NOW() - INTERVAL '7 days'
            GROUP BY day
            ORDER BY day
        """)).fetchall()

    if signup_rows:
        df = pd.DataFrame(signup_rows, columns=["날짜", "가입수"])
        df["날짜"] = pd.to_datetime(df["날짜"])
        st.bar_chart(df.set_index("날짜"))
    else:
        st.info("최근 7일 가입 데이터 없음")


# ══════════════════════════════════════════════════════════════════
# 메인 진입점
# ══════════════════════════════════════════════════════════════════

st.set_page_config(
    page_title="MomsTalk 관리자",
    page_icon="🏠",
    layout="wide",
)

if not _check_password():
    st.stop()

page = _sidebar()

if page == "captures":
    page_captures()
elif page == "reports":
    page_reports()
elif page == "users":
    page_users()
elif page == "dashboard":
    page_dashboard()
