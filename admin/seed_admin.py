"""
관리자 계정 초기 시드 스크립트.

사용법:
  cd admin
  python seed_admin.py

실행 시 .env 파일의 DATABASE_URL을 사용합니다.
이미 같은 username이 있으면 비밀번호만 업데이트합니다.
"""
import os
import getpass
import bcrypt
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()

_DATABASE_URL = os.environ.get("DATABASE_URL", "")
if not _DATABASE_URL:
    raise SystemExit("❌ .env 파일에 DATABASE_URL이 설정되지 않았습니다.")

_sync_url = (
    _DATABASE_URL
    .replace("postgresql+asyncpg://", "postgresql://")
    .replace("asyncpg://", "postgresql://")
)


def main() -> None:
    print("── MomsTalk 관리자 계정 생성 ──")
    username = input("사용자명 (기본: admin): ").strip() or "admin"
    password = getpass.getpass("비밀번호: ")
    confirm  = getpass.getpass("비밀번호 확인: ")

    if password != confirm:
        raise SystemExit("❌ 비밀번호가 일치하지 않습니다.")
    if len(password) < 8:
        raise SystemExit("❌ 비밀번호는 8자 이상이어야 합니다.")

    role = input("역할 (superadmin / moderator, 기본: superadmin): ").strip() or "superadmin"
    if role not in ("superadmin", "moderator"):
        raise SystemExit("❌ 역할은 superadmin 또는 moderator만 허용됩니다.")

    hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()

    engine = create_engine(_sync_url, future=True)
    with engine.begin() as conn:
        existing = conn.execute(
            text("SELECT id FROM admin_users WHERE username = :u"),
            {"u": username},
        ).fetchone()

        if existing:
            conn.execute(
                text("UPDATE admin_users SET hashed_password=:h, role=:r WHERE username=:u"),
                {"h": hashed, "r": role, "u": username},
            )
            print(f"✅ '{username}' 계정 비밀번호/역할 업데이트 완료")
        else:
            conn.execute(
                text("""
                    INSERT INTO admin_users (username, hashed_password, role, is_active, created_at)
                    VALUES (:u, :h, :r, true, NOW())
                """),
                {"u": username, "h": hashed, "r": role},
            )
            print(f"✅ '{username}' ({role}) 계정 생성 완료")

    print("\n관리자 대시보드: http://localhost:8501")
    print("또는 배포 후: https://api.momstalk.kr/admin/")


if __name__ == "__main__":
    main()
