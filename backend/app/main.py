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


async def _run_initial_sync():
    from app.services.academy_sync_service import initial_sync_if_needed
    from app.services.school_sync_service import initial_school_sync_if_needed
    try:
        await initial_school_sync_if_needed(settings.NEIS_API_KEY)
    except Exception as e:
        logger.error("학교 초기 동기화 실패: %s", e)
    try:
        await initial_sync_if_needed(settings.NEIS_API_KEY)
    except Exception as e:
        logger.error("학원 초기 동기화 실패: %s", e)


async def _weekly_sync():
    from app.services.academy_sync_service import sync_all_academies
    from app.services.school_sync_service import sync_all_schools
    logger.info("주간 동기화 시작")
    try:
        await sync_all_schools(settings.NEIS_API_KEY)
    except Exception as e:
        logger.error("주간 학교 동기화 실패: %s", e)
    try:
        await sync_all_academies(settings.NEIS_API_KEY, full=True)
    except Exception as e:
        logger.error("주간 학원 동기화 실패: %s", e)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 없는 테이블만 생성 (checkfirst=True → 기존 테이블 보존)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # 초기 동기화: 앱 시작 10초 후 백그라운드 실행 (포트 바인딩 먼저 완료)
    _scheduler.add_job(_run_initial_sync, "date", id="initial_sync",
                       run_date=None,  # 즉시이지만 scheduler 루프 안에서 실행
                       misfire_grace_time=600)
    # 매주 일요일 새벽 3시 전국 업데이트
    _scheduler.add_job(_weekly_sync, "cron", day_of_week="sun", hour=3, minute=0,
                       misfire_grace_time=3600)
    _scheduler.start()
    logger.info("APScheduler 시작 — 초기 동기화 및 매주 일 03:00 예약됨")

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
