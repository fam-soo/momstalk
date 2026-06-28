#!/bin/bash
set -e

# alembic_version 테이블에 복수 헤드가 있을 경우 가장 높은 번호만 남기고 정리
python - <<'PYEOF'
import os
from sqlalchemy import create_engine, text

db_url = os.environ.get("DATABASE_URL", "").replace("+asyncpg", "")
if not db_url:
    print("[start] DATABASE_URL 없음, 헤드 정리 건너뜀")
    exit(0)

try:
    engine = create_engine(db_url)
    with engine.connect() as conn:
        rows = conn.execute(text("SELECT version_num FROM alembic_version")).fetchall()
        heads = [r[0] for r in rows]
        print(f"[start] alembic 현재 헤드: {heads}")
        if len(heads) > 1:
            latest = max(heads)
            print(f"[start] 복수 헤드 감지 — {latest} 만 유지합니다")
            conn.execute(text("DELETE FROM alembic_version"))
            conn.execute(text(f"INSERT INTO alembic_version VALUES ('{latest}')"))
            conn.commit()
            print("[start] 헤드 정리 완료")
except Exception as e:
    print(f"[start] 헤드 정리 오류 (무시): {e}")
PYEOF

echo "[start] alembic upgrade head 실행 중..."
alembic upgrade head

echo "[start] uvicorn 시작"
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
