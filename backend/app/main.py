from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.db import engine
from app.models.service_models import Base


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 개발 환경에서 테이블 자동 생성 (production은 Alembic 사용)
    if settings.DEBUG:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
    yield


app = FastAPI(
    title=settings.APP_NAME,
    description="학부모 전용 익명 커뮤니티",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if settings.DEBUG else settings.allowed_origins_list,
    allow_credentials=not settings.DEBUG,
    allow_methods=["*"],
    allow_headers=["*"],
)

from app.api.v1.router import api_router  # noqa: E402
app.include_router(api_router, prefix="/api/v1")


@app.get("/health")
async def health():
    return {"status": "ok", "app": settings.APP_NAME}
