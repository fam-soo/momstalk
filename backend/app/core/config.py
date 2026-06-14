from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    APP_NAME: str = "MomsTalk"
    DEBUG: bool = False

    DATABASE_URL: str
    AUTH_DATABASE_URL: str
    REDIS_URL: str = "redis://localhost:6379/0"

    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # 익명화 해시용 별도 시크릿 (서비스 DB와 인증 DB 연결 고리 단절)
    ANON_HASH_SECRET: str

    SMS_API_KEY: str = ""
    SMS_API_SECRET: str = ""
    SMS_SENDER: str = ""

    NEIS_API_KEY: str = ""

    AWS_ACCESS_KEY_ID: str = ""
    AWS_SECRET_ACCESS_KEY: str = ""
    AWS_S3_BUCKET: str = "momstalk-media"
    AWS_REGION: str = "ap-northeast-2"

    ALLOWED_ORIGINS: str = "http://localhost:3000"

    @property
    def allowed_origins_list(self) -> list[str]:
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",")]

    class Config:
        env_file = ".env"


settings = Settings()
