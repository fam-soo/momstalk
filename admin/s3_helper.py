"""S3 presigned GET URL 생성."""
import os
import boto3
from botocore.exceptions import BotoCoreError, ClientError

_bucket = os.environ.get("AWS_S3_BUCKET", "momstalk-media")
_region = os.environ.get("AWS_REGION", "ap-northeast-2")


def get_presigned_url(s3_key: str, expires: int = 300) -> str | None:
    """캡처 이미지 미리보기용 presigned GET URL (5분 유효)."""
    key_id = os.environ.get("AWS_ACCESS_KEY_ID", "")
    if not key_id:
        return None  # 개발 환경 — 이미지 없음
    try:
        client = boto3.client(
            "s3",
            region_name=_region,
            aws_access_key_id=key_id,
            aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", ""),
        )
        return client.generate_presigned_url(
            "get_object",
            Params={"Bucket": _bucket, "Key": s3_key},
            ExpiresIn=expires,
        )
    except (BotoCoreError, ClientError):
        return None


def delete_object(s3_key: str) -> None:
    key_id = os.environ.get("AWS_ACCESS_KEY_ID", "")
    if not key_id:
        return
    try:
        client = boto3.client(
            "s3",
            region_name=_region,
            aws_access_key_id=key_id,
            aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", ""),
        )
        client.delete_object(Bucket=_bucket, Key=s3_key)
    except Exception:
        pass
