from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.pool import NullPool

from app.core.config import settings

engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    poolclass=NullPool,
    connect_args={"statement_cache_size": 0},
)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)

# 하위 호환 별칭 (리팩토링 완료 전 사용 중인 코드 대비)
service_engine = engine
ServiceSessionLocal = SessionLocal


async def get_db() -> AsyncSession:
    async with SessionLocal() as session:
        yield session


# 하위 호환 별칭
get_service_db = get_db
