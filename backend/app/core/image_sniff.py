"""이미지 매직 바이트 기반 실제 포맷 탐지.

클라이언트가 보낸 Content-Type 헤더는 라이브러리/플랫폼마다 누락되거나
잘못 설정되는 경우가 많아 신뢰할 수 없다 (Dio/http 패키지 구현체 교체 시마다
반복적으로 400 오류가 재발한 원인). 파일 바이트 자체를 검사해 실제 포맷을
판별하고, 그 결과로 허용 여부를 판단한다.
"""

_SIGNATURES: list[tuple[bytes, str]] = [
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"\x89PNG\r\n\x1a\n", "image/png"),
]


def sniff_image_mime(data: bytes) -> str | None:
    """파일 바이트에서 실제 이미지 MIME 타입을 추정. 판별 불가 시 None."""
    for signature, mime in _SIGNATURES:
        if data.startswith(signature):
            return mime
    if len(data) >= 12 and data[4:8] == b"ftyp":
        brand = data[8:12]
        if brand in (b"heic", b"heix", b"hevc", b"hevx", b"mif1", b"msf1"):
            return "image/heic"
    return None
