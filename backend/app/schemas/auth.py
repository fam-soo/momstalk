from pydantic import BaseModel, field_validator
import re


class SendSmsRequest(BaseModel):
    phone_number: str  # 010-XXXX-XXXX 또는 01XXXXXXXXX

    @field_validator("phone_number")
    @classmethod
    def normalize_phone(cls, v: str) -> str:
        digits = re.sub(r"\D", "", v)
        if not re.match(r"^01[0-9]{8,9}$", digits):
            raise ValueError("올바른 휴대폰 번호를 입력해주세요.")
        return digits


class VerifySmsRequest(BaseModel):
    phone_number: str
    code: str

    @field_validator("phone_number")
    @classmethod
    def normalize_phone(cls, v: str) -> str:
        return re.sub(r"\D", "", v)


class VerifySmsResponse(BaseModel):
    sms_token: str  # 단기 토큰 — 학부모 인증 단계에서만 사용


class ParentVerifyRequest(BaseModel):
    sms_token: str
    region: str
    school_code: str
    school_name: str
    grade: int
    school_type: str  # elementary / middle / high

    @field_validator("grade")
    @classmethod
    def check_grade(cls, v: int) -> int:
        if not (1 <= v <= 6):
            raise ValueError("학년은 1~6 사이여야 합니다.")
        return v

    @field_validator("school_type")
    @classmethod
    def check_school_type(cls, v: str) -> str:
        if v not in ("elementary", "middle", "high"):
            raise ValueError("school_type은 elementary / middle / high 중 하나여야 합니다.")
        return v


class DevLoginRequest(BaseModel):
    """[개발 전용] 인증번호 없이 로그인할 때 사용."""
    phone_number: str
    region: str = "강남구"
    school_code: str
    school_name: str
    grade: int
    school_type: str

    @field_validator("phone_number")
    @classmethod
    def normalize_phone(cls, v: str) -> str:
        digits = re.sub(r"\D", "", v)
        if not re.match(r"^01[0-9]{8,9}$", digits):
            raise ValueError("올바른 휴대폰 번호를 입력해주세요.")
        return digits

    @field_validator("grade")
    @classmethod
    def check_grade(cls, v: int) -> int:
        if not (1 <= v <= 6):
            raise ValueError("학년은 1~6 사이여야 합니다.")
        return v

    @field_validator("school_type")
    @classmethod
    def check_school_type(cls, v: str) -> str:
        if v not in ("elementary", "middle", "high"):
            raise ValueError("school_type은 elementary / middle / high 중 하나여야 합니다.")
        return v


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshRequest(BaseModel):
    refresh_token: str


class KakaoLoginRequest(BaseModel):
    kakao_access_token: str


class CapturePresignResponse(BaseModel):
    upload_url: str
    s3_key: str
    skip_upload: bool = False  # True이면 S3 미설정(개발 환경) → 클라이언트가 PUT 생략


class CaptureSubmitRequest(BaseModel):
    s3_key: str
    school_code: str
    school_name: str
    grade: int
    class_num: int | None = None
    school_type: str


class InviteGenerateResponse(BaseModel):
    token: str
    expires_at: str
    deeplink: str


class InviteUseRequest(BaseModel):
    token: str
    grade: int
    class_num: int | None = None


class AdminLoginRequest(BaseModel):
    username: str
    password: str
