import asyncio
import logging
import time
from contextlib import asynccontextmanager

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.db import engine
from app.models.service_models import Base


# 앱 어디서든 logging.getLogger(__name__)로 로그를 남기면 Render 로그(stdout)에
# 보이도록 루트 로거를 설정한다. 이게 없으면 루트 로거 기본 레벨(WARNING)에
# 걸려 logger.info(...) 호출이 전부 조용히 사라진다 — FCM 발송 성공/스킵
# 로그가 전혀 안 보이던 원인이었음.
logging.basicConfig(level=logging.INFO, format="%(levelname)s:%(name)s:%(message)s")

logger = logging.getLogger(__name__)

_scheduler = AsyncIOScheduler(timezone="Asia/Seoul")


async def _run_initial_sync():
    """앱 시작 후 백그라운드에서 학교·학원 초기 동기화."""
    from app.services.school_sync_service import initial_school_sync_if_needed
    from app.services.academy_sync_service import initial_sync_if_needed

    logger.info("=== 초기 동기화 시작 ===")
    try:
        await initial_school_sync_if_needed(settings.NEIS_API_KEY)
    except Exception as e:
        logger.error("학교 초기 동기화 실패: %s", e)
    try:
        await initial_sync_if_needed(settings.NEIS_API_KEY)
    except Exception as e:
        logger.error("학원 초기 동기화 실패: %s", e)
    logger.info("=== 초기 동기화 완료 ===")


async def _weekly_sync():
    from app.services.school_sync_service import sync_all_schools
    from app.services.academy_sync_service import sync_all_academies
    logger.info("주간 동기화 시작")
    try:
        await sync_all_schools(settings.NEIS_API_KEY)
        await sync_all_academies(settings.NEIS_API_KEY, full=True)
    except Exception as e:
        logger.error("주간 동기화 실패: %s", e)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 없는 테이블만 생성 (기존 테이블 보존)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # 초기 동기화: 백그라운드 태스크로 즉시 실행
    _sync_task = asyncio.create_task(_run_initial_sync())

    # 매주 일요일 03:00 전국 업데이트
    _scheduler.add_job(_weekly_sync, "cron", day_of_week="sun", hour=3, minute=0,
                       misfire_grace_time=3600)
    _scheduler.start()
    logger.info("APScheduler 시작 (매주 일 03:00)")

    yield

    _sync_task.cancel()
    _scheduler.shutdown(wait=False)


app = FastAPI(
    title=settings.APP_NAME,
    description="학부모 전용 익명 커뮤니티",
    version="0.1.0",
    lifespan=lifespan,
)

# 글로벌 Rate Limit 미들웨어 — IP당 분당 200회 초과 시 429
_global_rl_store: dict[str, list[float]] = {}


@app.middleware("http")
async def global_rate_limit(request: Request, call_next) -> Response:
    if not request.url.path.startswith("/api/"):
        return await call_next(request)
    forwarded = request.headers.get("X-Forwarded-For")
    ip = forwarded.split(",")[0].strip() if forwarded else (
        request.client.host if request.client else "unknown"
    )
    now = time.time()
    window = 60.0
    limit = 200
    hits = _global_rl_store.get(ip, [])
    hits = [t for t in hits if now - t < window]
    hits.append(now)
    _global_rl_store[ip] = hits
    if len(hits) > limit:
        return Response(
            content='{"detail":"요청이 너무 많습니다. 잠시 후 다시 시도해주세요."}',
            status_code=429,
            headers={"Content-Type": "application/json", "Retry-After": "60"},
        )
    return await call_next(request)


# CORSMiddleware는 반드시 위의 global_rate_limit보다 나중에 등록해야 한다.
# Starlette는 가장 나중에 add_middleware()된 것이 최외곽(outermost) 레이어가
# 되는데, CORSMiddleware가 global_rate_limit 안쪽에 있으면 429처럼 미들웨어가
# 직접 반환하는 Response에는 CORS 헤더가 붙지 않는다. 브라우저는 이런 응답을
# 오리진 정책 위반으로 보고 차단하며, 그 결과가 JS 코드에는 원인을 알 수 없는
# "네트워크 오류"로만 보인다 (모바일 브라우저에서 재시도가 잦을수록 이 429를
# 더 자주 유발해 재현되기 쉬웠음).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


from app.api.v1.router import api_router  # noqa: E402
app.include_router(api_router, prefix="/api/v1")


@app.get("/health")
async def health():
    return {"status": "ok", "app": settings.APP_NAME}


@app.get("/internal/sync")
async def trigger_sync():
    """수동 동기화 트리거 — 브라우저에서 URL 열기."""
    asyncio.create_task(_run_initial_sync())
    return {"ok": True, "message": "동기화 시작됨 — Render 로그에서 진행 확인"}


@app.get("/internal/db-count")
async def db_count():
    """DB 학교·학원 수 확인."""
    from sqlalchemy import select, func
    from app.db import SessionLocal
    from app.models.service_models import School, Academy
    async with SessionLocal() as db:
        school_cnt = (await db.execute(select(func.count(School.id)))).scalar_one()
        academy_cnt = (await db.execute(select(func.count(Academy.id)))).scalar_one()
    return {"schools": school_cnt, "academies": academy_cnt}
