#!/bin/bash
set -e

# DB 실제 상태와 alembic_version을 동기화한 뒤 upgrade head 실행
python - <<'PYEOF'
import os
from sqlalchemy import create_engine, text, inspect

db_url = os.environ.get("DATABASE_URL", "").replace("+asyncpg", "")
if not db_url:
    print("[start] DATABASE_URL 없음, 건너뜀")
    exit(0)

try:
    engine = create_engine(db_url)
    with engine.connect() as conn:
        # 1. 현재 alembic 헤드 목록 확인
        rows = conn.execute(text("SELECT version_num FROM alembic_version")).fetchall()
        heads = [r[0] for r in rows]
        print(f"[start] alembic 현재 헤드: {heads}")

        # 2. 복수 헤드면 가장 높은 것만 유지
        if len(heads) > 1:
            latest = max(heads)
            print(f"[start] 복수 헤드 → {latest} 만 유지")
            conn.execute(text("DELETE FROM alembic_version"))
            conn.execute(text(f"INSERT INTO alembic_version VALUES ('{latest}')"))
            conn.commit()
            heads = [latest]
            print("[start] 헤드 정리 완료")

        # 3. 실제 DB에 schools 테이블이 있으면 0012가 적용된 것으로 간주
        inspector = inspect(engine)
        tables = inspector.get_table_names()
        current = heads[0] if heads else None
        print(f"[start] 현재 헤드: {current}, 테이블 목록 일부: {[t for t in tables if t in ('schools','academy_reviews','alembic_version')]}")

        if current and int(current) < 12 and "schools" in tables:
            print("[start] schools 테이블 존재 → 0012 이미 적용된 것으로 stamp")
            conn.execute(text("DELETE FROM alembic_version"))
            conn.execute(text("INSERT INTO alembic_version VALUES ('0012')"))
            conn.commit()
            print("[start] stamp 0012 완료")

        # 4. academy_reviews에 subjects 컬럼이 있으면 0013도 적용된 것으로 간주
        if "academy_reviews" in tables:
            cols = [c["name"] for c in inspector.get_columns("academy_reviews")]
            heads_now = conn.execute(text("SELECT version_num FROM alembic_version")).fetchall()
            current2 = heads_now[0][0] if heads_now else current
            if int(current2) < 13 and "subjects" in cols:
                print("[start] subjects 컬럼 존재 → 0013 이미 적용된 것으로 stamp")
                conn.execute(text("DELETE FROM alembic_version"))
                conn.execute(text("INSERT INTO alembic_version VALUES ('0013')"))
                conn.commit()
                print("[start] stamp 0013 완료")

except Exception as e:
    print(f"[start] 사전 동기화 오류 (무시): {e}")
PYEOF

echo "[start] alembic upgrade head 실행..."
alembic upgrade head

echo "[start] uvicorn 시작"
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
