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

    # 카카오 로그인
    KAKAO_CLIENT_ID: str = ""           # REST API 키
    KAKAO_REDIRECT_URI: str = ""        # 앱 딥링크 (카카오 콘솔 등록 필요)

    # 추천 링크 기본 딥링크 스킴
    INVITE_DEEPLINK_BASE: str = "momstalk://invite"

    # Firebase Cloud Messaging — service account JSON 내용을 그대로 환경변수에 주입
    # 값이 없으면 FCM 발송 없이 무시 (graceful degradation)
    FCM_SERVICE_ACCOUNT_JSON: str = ""

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
