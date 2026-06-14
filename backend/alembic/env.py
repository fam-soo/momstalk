import asyncio
from logging.config import fileConfig

from sqlalchemy.ext.asyncio import create_async_engine
from alembic import context

from app.core.config import settings
from app.models.service_models import Base
from app.models.auth_models import AuthBase

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# 두 DB 중 어느 쪽을 마이그레이션할지 환경변수로 선택
# ALEMBIC_TARGET=auth → 인증 DB, 그 외 → 서비스 DB
import os
ALEMBIC_TARGET = os.getenv("ALEMBIC_TARGET", "service")

if ALEMBIC_TARGET == "auth":
    target_metadata = AuthBase.metadata
    db_url = settings.AUTH_DATABASE_URL
else:
    target_metadata = Base.metadata
    db_url = settings.DATABASE_URL


def run_migrations_offline() -> None:
    context.configure(
        url=db_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection):
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    engine = create_async_engine(db_url)
    async with engine.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
