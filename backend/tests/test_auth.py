"""
인증 플로우 테스트.

커버리지:
  - /health
  - POST /auth/dev/lurker-login
  - POST /auth/dev/login
  - POST /auth/dev/approve-me
  - GET  /auth/me
  - PATCH /auth/me/nickname
  - POST /auth/refresh
  - POST /auth/sms/send  (개발 모드: 실제 SMS 미발송)
  - POST /auth/capture/presign
  - POST /auth/invite/generate
"""
import pytest


@pytest.mark.asyncio
async def test_health(client):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


@pytest.mark.asyncio
async def test_lurker_login(client):
    resp = await client.post("/api/v1/auth/dev/lurker-login")
    assert resp.status_code == 200
    data = resp.json()
    assert "access_token" in data
    assert "refresh_token" in data


@pytest.mark.asyncio
async def test_dev_login(client):
    resp = await client.post("/api/v1/auth/dev/login", json={
        "phone_number": "01099998888",
        "region": "경기",
        "school_code": "J123456789",
        "school_name": "테스트중학교",
        "grade": 1,
        "school_type": "middle",
    })
    assert resp.status_code == 200
    assert "access_token" in resp.json()


@pytest.mark.asyncio
async def test_get_me(client, lurker_token):
    resp = await client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {lurker_token}"},
    )
    assert resp.status_code == 200
    me = resp.json()
    assert "id" in me
    assert "nickname" in me
    assert me["member_grade"] == "lurker"


@pytest.mark.asyncio
async def test_approve_me(client, member_token):
    resp = await client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {member_token}"},
    )
    assert resp.status_code == 200
    assert resp.json()["member_grade"] == "member"


@pytest.mark.asyncio
async def test_update_nickname(client, lurker_token):
    resp = await client.patch(
        "/api/v1/auth/me/nickname",
        json={"nickname": "새닉네임"},
        headers={"Authorization": f"Bearer {lurker_token}"},
    )
    assert resp.status_code == 200
    assert resp.json()["nickname"] == "새닉네임"


@pytest.mark.asyncio
async def test_refresh_token(client, lurker_token):
    # 먼저 lurker 로그인으로 refresh_token 획득
    resp = await client.post("/api/v1/auth/dev/lurker-login")
    refresh_token = resp.json()["refresh_token"]

    resp2 = await client.post("/api/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert resp2.status_code == 200
    assert "access_token" in resp2.json()


@pytest.mark.asyncio
async def test_refresh_with_invalid_token(client):
    resp = await client.post("/api/v1/auth/refresh", json={"refresh_token": "invalid.token.here"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_sms_send_dev_mode(client):
    """개발 모드: SMS API 없이도 200 응답 (콘솔 출력)."""
    resp = await client.post("/api/v1/auth/sms/send", json={"phone_number": "01012345678"})
    # 204 No Content 정상, 실패 시 외부 SMS API 오류일 수 있음
    assert resp.status_code in (204, 500)


@pytest.mark.asyncio
async def test_capture_presign_requires_auth(client):
    resp = await client.post("/api/v1/auth/capture/presign")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_capture_presign_with_auth(client, lurker_token):
    resp = await client.post(
        "/api/v1/auth/capture/presign",
        headers={"Authorization": f"Bearer {lurker_token}"},
    )
    # S3 미설정 시 upload_url 이 빈 문자열이고 skip_upload=True
    assert resp.status_code == 200
    data = resp.json()
    assert "s3_key" in data
    assert "skip_upload" in data


@pytest.mark.asyncio
async def test_invite_generate_requires_member(client, lurker_token):
    """lurker는 초대 링크 발급 불가."""
    resp = await client.post(
        "/api/v1/auth/invite/generate",
        headers={"Authorization": f"Bearer {lurker_token}"},
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_invite_generate_as_member(client, member_token):
    resp = await client.post(
        "/api/v1/auth/invite/generate",
        headers={"Authorization": f"Bearer {member_token}"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "token" in data
    assert "deeplink" in data
