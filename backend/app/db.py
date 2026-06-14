from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker

from app.core.config import settings

# 서비스 DB 엔진 (게시글, 댓글, 유저 — 신원 정보 없음)
service_engine = create_async_engine(settings.DATABASE_URL, echo=settings.DEBUG)
ServiceSessionLocal = async_sessionmaker(service_engine, expire_on_commit=False)

# 인증 DB 엔진 (전화번호, 학부모 인증 레코드 — 물리적 분리)
auth_engine = create_async_engine(settings.AUTH_DATABASE_URL, echo=settings.DEBUG)
AuthSessionLocal = async_sessionmaker(auth_engine, expire_on_commit=False)


async def get_service_db() -> AsyncSession:
    async with ServiceSessionLocal() as session:
        yield session


async def get_auth_db() -> AsyncSession:
    async with AuthSessionLocal() as session:
        yield session
