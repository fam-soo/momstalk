from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.pool import NullPool

from app.core.config import settings

engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    poolclass=NullPool,
    connect_args={"prepare_threshold": None},  # psycopg3: prepared statement 완전 비활성화
)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)

# 하위 호환 별칭
service_engine = engine
ServiceSessionLocal = SessionLocal


async def get_db() -> AsyncSession:
    async with SessionLocal() as session:
        yield session


# 하위 호환 별칭
get_service_db = get_db
