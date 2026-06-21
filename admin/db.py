"""동기 SQLAlchemy 세션 (Streamlit는 async 불필요)."""
import os
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

load_dotenv()

_DATABASE_URL = os.environ["DATABASE_URL"]
# asyncpg → psycopg2 드라이버로 교체
_sync_url = _DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://").replace("asyncpg://", "postgresql://")

engine = create_engine(_sync_url, pool_pre_ping=True, future=True)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
