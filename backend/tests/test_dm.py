"""
DM(다이렉트 메시지) · 차단 테스트.

커버리지:
  - POST /conversations/{other_user_id}   — 대화방 생성/조회
  - GET  /conversations                   — 대화방 목록
  - POST /conversations/{conv_id}/messages — 메시지 전송
  - GET  /conversations/{conv_id}/messages — 메시지 목록
  - POST /users/{target_id}/block          — 차단
  - DELETE /users/{target_id}/block        — 차단 해제
"""
import pytest

AUTH = lambda token: {"Authorization": f"Bearer {token}"}


async def _create_second_member(client):
    """두 번째 정회원 계정 생성 후 토큰 반환."""
    resp = await client.post("/api/v1/auth/dev/login", json={
        "phone_number": "01077776666",
        "region": "부산",
        "school_code": "D987654321",
        "school_name": "두번째초등학교",
        "grade": 3,
        "school_type": "elementary",
    })
    token = resp.json()["access_token"]
    await client.post("/api/v1/auth/dev/approve-me", headers=AUTH(token))
    return token


@pytest.mark.asyncio
async def test_dm_flow(client, member_token):
    token2 = await _create_second_member(client)

    # 유저 2의 ID 조회
    me2 = await client.get("/api/v1/auth/me", headers=AUTH(token2))
    user2_id = me2.json()["id"]

    # 유저 1이 유저 2에게 대화방 생성
    conv_resp = await client.post(
        f"/api/v1/conversations/{user2_id}",
        headers=AUTH(member_token),
    )
    assert conv_resp.status_code == 200
    conv_id = conv_resp.json()["id"]

    # 대화방 목록 확인
    list_resp = await client.get("/api/v1/conversations", headers=AUTH(member_token))
    assert list_resp.status_code == 200
    convs = list_resp.json()
    assert any(c["id"] == conv_id for c in convs)

    # 메시지 전송
    msg_resp = await client.post(
        f"/api/v1/conversations/{conv_id}/messages",
        json={"content": "안녕하세요!"},
        headers=AUTH(member_token),
    )
    assert msg_resp.status_code == 201
    assert msg_resp.json()["content"] == "안녕하세요!"

    # 메시지 목록 조회
    msgs_resp = await client.get(
        f"/api/v1/conversations/{conv_id}/messages",
        headers=AUTH(member_token),
    )
    assert msgs_resp.status_code == 200
    messages = msgs_resp.json()
    assert len(messages) >= 1
    assert messages[0]["content"] == "안녕하세요!"

    # 유저 2도 같은 대화방에서 메시지 조회 가능
    msgs_resp2 = await client.get(
        f"/api/v1/conversations/{conv_id}/messages",
        headers=AUTH(token2),
    )
    assert msgs_resp2.status_code == 200


@pytest.mark.asyncio
async def test_block_unblock(client, member_token):
    token2 = await _create_second_member(client)
    me2 = await client.get("/api/v1/auth/me", headers=AUTH(token2))
    user2_id = me2.json()["id"]

    # 차단
    block_resp = await client.post(
        f"/api/v1/users/{user2_id}/block",
        headers=AUTH(member_token),
    )
    assert block_resp.status_code == 204

    # 차단 해제
    unblock_resp = await client.delete(
        f"/api/v1/users/{user2_id}/block",
        headers=AUTH(member_token),
    )
    assert unblock_resp.status_code == 204


@pytest.mark.asyncio
async def test_cannot_dm_self(client, member_token):
    me = await client.get("/api/v1/auth/me", headers=AUTH(member_token))
    my_id = me.json()["id"]

    resp = await client.post(
        f"/api/v1/conversations/{my_id}",
        headers=AUTH(member_token),
    )
    assert resp.status_code == 400
