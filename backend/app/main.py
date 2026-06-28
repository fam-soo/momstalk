import logging
from contextlib import asynccontextmanager

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.db import engine
from app.models.service_models import Base

logger = logging.getLogger(__name__)

_scheduler = AsyncIOScheduler(timezone="Asia/Seoul")


async def _weekly_sync():
    from app.services.academy_sync_service import sync_all_academies
    logger.info("주간 학원 동기화 시작")
    await sync_all_academies(settings.NEIS_API_KEY, full=True)


@asynccontextmanager
async def lifespan(app: FastAPI):
    if settings.DEBUG:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    # 최초 동기화: 백그라운드로 실행 (Render 포트 감지 차단 방지)
    import asyncio
    from app.services.academy_sync_service import initial_sync_if_needed

    async def _bg_initial_sync():
        try:
            await initial_sync_if_needed(settings.NEIS_API_KEY)
        except Exception as e:
            logger.error("초기 학원 동기화 실패: %s", e)

    asyncio.get_event_loop().create_task(_bg_initial_sync())

    # 매주 일요일 새벽 3시 전국 업데이트
    _scheduler.add_job(_weekly_sync, "cron", day_of_week="sun", hour=3, minute=0)
    _scheduler.start()
    logger.info("APScheduler 시작 (매주 일 03:00 학원 동기화)")

    yield

    _scheduler.shutdown(wait=False)


app = FastAPI(
    title=settings.APP_NAME,
    description="학부모 전용 익명 커뮤니티",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

from app.api.v1.router import api_router  # noqa: E402
app.include_router(api_router, prefix="/api/v1")


@app.get("/health")
async def health():
    return {"status": "ok", "app": settings.APP_NAME}
