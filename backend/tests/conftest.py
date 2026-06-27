"""
pytest 공통 픽스처.

실행 전 환경변수 설정:
  DATABASE_URL / AUTH_DATABASE_URL 에 테스트 전용 DB URL을 지정하거나,
  SQLite 인메모리 DB(aiosqlite)를 사용하면 외부 의존 없이 실행 가능.

  pip install aiosqlite pytest-asyncio httpx
"""
import os
import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker

# 테스트 전용 SQLite 인메모리 DB 사용
TEST_DB_URL = "sqlite+aiosqlite:///./test.db"
TEST_AUTH_DB_URL = "sqlite+aiosqlite:///./test_auth.db"

os.environ["DATABASE_URL"] = TEST_DB_URL
os.environ["AUTH_DATABASE_URL"] = TEST_AUTH_DB_URL
os.environ["SECRET_KEY"] = "test-secret-key-for-pytest-only"
os.environ["ANON_HASH_SECRET"] = "test-anon-hash-secret"
os.environ["DEBUG"] = "true"
os.environ["REDIS_URL"] = "redis://localhost:6379/0"

from app.main import app
from app.db import get_service_db, get_auth_db
from app.models.auth_models import AuthBase
from app.models.service_models import Base


_service_engine = create_async_engine(TEST_DB_URL, echo=False)
_auth_engine = create_async_engine(TEST_AUTH_DB_URL, echo=False)
_ServiceSession = async_sessionmaker(_service_engine, expire_on_commit=False)
_AuthSession = async_sessionmaker(_auth_engine, expire_on_commit=False)


@pytest_asyncio.fixture(scope="session", autouse=True)
async def setup_db():
    async with _service_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with _auth_engine.begin() as conn:
        await conn.run_sync(AuthBase.metadata.create_all)
    yield
    async with _service_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    async with _auth_engine.begin() as conn:
        await conn.run_sync(AuthBase.metadata.drop_all)


@pytest_asyncio.fixture()
async def client():
    """앱 의존성을 테스트 DB로 오버라이드한 AsyncClient."""
    async def _override_service_db():
        async with _ServiceSession() as session:
            yield session

    async def _override_auth_db():
        async with _AuthSession() as session:
            yield session

    app.dependency_overrides[get_service_db] = _override_service_db
    app.dependency_overrides[get_auth_db] = _override_auth_db

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac

    app.dependency_overrides.clear()


@pytest_asyncio.fixture()
async def lurker_token(client: AsyncClient) -> str:
    """개발 전용 lurker 로그인 토큰 (member_grade=lurker)."""
    resp = await client.post("/api/v1/auth/dev/lurker-login")
    assert resp.status_code == 200, resp.text
    return resp.json()["access_token"]


@pytest_asyncio.fixture()
async def member_token(client: AsyncClient) -> str:
    """개발 전용 정회원 토큰 (dev/login → dev/approve-me)."""
    resp = await client.post("/api/v1/auth/dev/login", json={
        "phone_number": "01011112222",
        "region": "서울",
        "school_code": "B100000393",
        "school_name": "테스트초등학교",
        "grade": 2,
        "school_type": "elementary",
    })
    assert resp.status_code == 200, resp.text
    token = resp.json()["access_token"]

    # lurker → member 승급
    await client.post(
        "/api/v1/auth/dev/approve-me",
        headers={"Authorization": f"Bearer {token}"},
    )
    return token
